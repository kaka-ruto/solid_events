# frozen_string_literal: true
require "digest"
require "json"
require "time"

module SolidEvents
  module Tracer
    module_function

    def start_trace!(name:, trace_type:, source:, context: {})
      return unless storage_available?

      trace = SolidEvents::Trace.create!(
        name: name,
        trace_type: trace_type,
        source: source,
        context: normalize_context(context),
        started_at: Time.current
      )
      SolidEvents::Current.trace = trace
      trace
    end

    def current_trace
      SolidEvents::Current.trace
    end

    def finish_trace!(status: "ok", context: {})
      return unless storage_available?

      trace = current_trace
      return unless trace

      existing_context = normalize_context(trace.context.to_h)
      extra_context = normalize_context(context)
      final_context = existing_context.merge(extra_context)
      trace.update!(status: status, finished_at: Time.current, context: final_context)

      unless keep_trace?(trace, context: final_context)
        trace.destroy!
        SolidEvents::Current.trace = nil
        return nil
      end

      upsert_summary!(trace)
      emit_canonical_log_line!(trace)
      SolidEvents::Current.trace = nil
      trace
    end

    def record_event!(event_type:, name:, payload: {}, duration_ms: nil)
      return unless storage_available?

      trace = current_trace
      return unless trace

      trace.events.create!(
        event_type: event_type,
        name: name,
        payload: payload,
        duration_ms: duration_ms,
        occurred_at: Time.current
      )
      upsert_summary!(trace)
    end

    def link_record!(record)
      return unless storage_available?

      trace = current_trace
      return unless trace
      return if record.is_a?(SolidEvents::Record)
      return if SolidEvents.ignore_models.include?(record.class.name)
      return if SolidEvents.ignore_model_prefixes.any? { |prefix| record.class.name.start_with?(prefix.to_s) }

      trace.record_links.find_or_create_by!(record_type: record.class.name, record_id: record.id)
      upsert_summary!(trace)
    end

    def link_error!(solid_error_id)
      return unless storage_available?

      trace = current_trace
      return unless trace

      trace.error_links.find_or_create_by!(solid_error_id: solid_error_id)
      upsert_summary!(trace)
    end

    def bind_exception_to_trace!(exception, trace: current_trace)
      return unless storage_available?
      return unless exception && trace

      bindings = SolidEvents::Current.error_trace_bindings
      bindings[exception.object_id] = trace.id
      SolidEvents::Current.error_trace_bindings = bindings
    end

    def consume_bound_trace_for_exception(exception)
      return unless storage_available?
      return unless exception

      bindings = SolidEvents::Current.error_trace_bindings
      trace_id = bindings.delete(exception.object_id)
      SolidEvents::Current.error_trace_bindings = bindings
      return unless trace_id

      SolidEvents::Trace.find_by(id: trace_id)
    end

    def reconcile_error_link_for_trace!(trace, attempts: 6, exception: nil)
      return unless storage_available?
      return unless trace
      return unless defined?(SolidErrors::Error)
      return if trace.error_links.exists?

      fingerprint = trace.context.to_h["error_fingerprint"]
      if fingerprint.present?
        by_fingerprint = SolidErrors::Error.find_by(fingerprint: fingerprint)
        if by_fingerprint
          trace.error_links.find_or_create_by!(solid_error_id: by_fingerprint.id)
          return by_fingerprint
        end
      end

      candidates = error_candidates_from(exception: exception, trace: trace)
      if candidates.empty?
        by_occurrence = find_solid_error_by_occurrence(trace)
        if by_occurrence
          trace.error_links.find_or_create_by!(solid_error_id: by_occurrence.id)
          return by_occurrence
        end
        return
      end

      attempts.times do |attempt|
        solid_error = find_matching_solid_error(candidates: candidates, trace: trace)

        if solid_error
          trace.error_links.find_or_create_by!(solid_error_id: solid_error.id)
          return solid_error
        end

        sleep(0.03 * (attempt + 1))
      end

      nil
    rescue StandardError
      nil
    end

    def reconcile_recent_error_links!(limit: 25)
      return unless storage_available?
      return unless defined?(SolidErrors::Error)

      SolidEvents::Trace
        .where(status: "error")
        .where("finished_at >= ?", 1.hour.ago)
        .left_joins(:error_links)
        .where(solid_events_error_links: {id: nil})
        .order(finished_at: :desc)
        .limit(limit)
        .each do |trace|
          reconcile_error_link_for_trace!(trace, attempts: 1)
        end
    end

    def normalize_context(context)
      return {} unless context.respond_to?(:to_h)

      context.to_h.transform_keys(&:to_s)
    end

    def sanitize_exception_message(message)
      return message.to_s unless defined?(SolidErrors::Sanitizer)

      SolidErrors::Sanitizer.sanitize(message.to_s)
    rescue StandardError
      message.to_s
    end

    def error_fingerprint_for(exception, severity:, source:)
      candidate = root_cause(exception)
      message = sanitize_exception_message(candidate.message)
      Digest::SHA256.hexdigest([candidate.class.name, message, severity, source].join)
    end

    def storage_available?
      return @storage_available unless @storage_available.nil?

      @storage_available = begin
        connection = SolidEvents::Trace.connection
        connection.data_source_exists?(SolidEvents::Trace.table_name) &&
          connection.data_source_exists?(SolidEvents::Event.table_name) &&
          connection.data_source_exists?(SolidEvents::RecordLink.table_name) &&
          connection.data_source_exists?(SolidEvents::ErrorLink.table_name)
      rescue StandardError
        false
      end
    end

    def reset_storage_availability_cache!
      @storage_available = nil
      @summary_storage_available = nil
    end

    def summary_storage_available?
      return @summary_storage_available unless @summary_storage_available.nil?

      @summary_storage_available = begin
        SolidEvents::Summary.connection.data_source_exists?(SolidEvents::Summary.table_name)
      rescue StandardError
        false
      end
    end

    def upsert_summary!(trace)
      return unless trace
      return unless summary_storage_available?

      context = trace.context.to_h
      entity = extract_primary_entity(trace)
      http_status = context["status"].presence&.to_i

      summary = SolidEvents::Summary.find_or_initialize_by(trace_id: trace.id)
      summary.assign_attributes(
        name: trace.name,
        trace_type: trace.trace_type,
        source: trace.source,
        status: trace.status,
        outcome: trace.status == "error" ? "failure" : "success",
        entity_type: entity[:type],
        entity_id: entity[:id],
        http_status: http_status,
        request_method: context["method"],
        path: context["path"],
        job_class: trace.trace_type == "job" ? trace.source : nil,
        queue_name: context["queue"],
        started_at: trace.started_at,
        finished_at: trace.finished_at,
        duration_ms: trace.finished_at && trace.started_at ? ((trace.finished_at - trace.started_at) * 1000.0).round(2) : nil,
        event_count: trace.events.count,
        record_link_count: trace.record_links.count,
        error_count: trace.error_links.count,
        user_id: context["user_id"],
        account_id: context["account_id"],
        error_fingerprint: context["error_fingerprint"],
        payload: {
          event_counts: trace.events.group(:event_type).count,
          error_link_ids: trace.error_links.pluck(:solid_error_id),
          context: context
        }
      )
      summary.save!
      summary
    rescue StandardError
      nil
    end

    def keep_trace?(trace, context:)
      duration_ms = if trace.finished_at && trace.started_at
        ((trace.finished_at - trace.started_at) * 1000.0).round(2)
      end

      status_code = context["status"].to_i if context.key?("status")
      return true if trace.status == "error"
      return true if status_code && status_code >= 500
      return true if duration_ms && duration_ms >= SolidEvents.tail_sample_slow_ms

      always_sample_key_hit = SolidEvents.always_sample_context_keys.any? do |key|
        value = context[key]
        value.present? && value != false
      end
      return true if always_sample_key_hit

      if SolidEvents.always_sample_when.respond_to?(:call)
        return true if SolidEvents.always_sample_when.call(trace: trace, context: context, duration_ms: duration_ms)
      end

      sample_rate = SolidEvents.sample_rate.clamp(0.0, 1.0)
      return true if sample_rate >= 1.0
      return false if sample_rate <= 0.0

      rand < sample_rate
    rescue StandardError
      true
    end

    def emit_canonical_log_line!(trace)
      return unless SolidEvents.emit_canonical_log_line?
      return unless defined?(Rails) && Rails.logger

      payload = trace.canonical_event
      payload[:emitted_at] = Time.current.iso8601
      Rails.logger.info(payload.to_json)
    rescue StandardError
      nil
    end

    def extract_primary_entity(trace)
      link = trace.record_links.order(:created_at, :id).first
      return {type: nil, id: nil} unless link

      {type: link.record_type, id: link.record_id}
    rescue StandardError
      {type: nil, id: nil}
    end

    def error_candidates_from(exception:, trace:)
      if exception
        chain = exception_chain(exception)
        chain.map { |ex| [ex.class.name, sanitize_exception_message(ex.message)] }.uniq
      else
        context = trace.context.to_h
        pairs = []
        pairs << [context["exception_class"], sanitize_exception_message(context["exception_message"])]
        pairs << [context["root_exception_class"], sanitize_exception_message(context["root_exception_message"])]
        pairs.reject { |klass, msg| klass.blank? || msg.blank? }.uniq
      end
    end

    def find_matching_solid_error(candidates:, trace:)
      candidates.each do |exception_class, sanitized_message|
        exact = SolidErrors::Error.where(
          exception_class: exception_class,
          message: sanitized_message
        ).order(updated_at: :desc).first
        return exact if exact
      end

      # Fallback for wrapper exceptions (e.g. ActionView::Template::Error wrapping NameError)
      # where SolidErrors stores the root cause class but message is still exact.
      message_only = candidates.filter_map { |(_, msg)| msg.presence }.uniq
      return nil if message_only.empty?

      scope = SolidErrors::Error.where(message: message_only)
      if trace.finished_at
        scope = scope.where(updated_at: (trace.started_at - 5.minutes)..(trace.finished_at + 5.minutes))
      end
      scope.order(updated_at: :desc).first
    end

    def find_solid_error_by_occurrence(trace)
      return unless defined?(SolidErrors::Occurrence)
      return unless trace.started_at && trace.finished_at

      range = (trace.started_at - 3.seconds)..(trace.finished_at + 3.seconds)
      occurrences = SolidErrors::Occurrence
        .includes(:error)
        .where(created_at: range)
        .order(created_at: :desc)
        .limit(10)

      controller_name = trace.source.to_s.split("#").first
      scored = occurrences.filter_map do |occurrence|
        next unless occurrence.error
        controller_context = occurrence.context.to_h["controller"].to_s
        next if controller_name.present? && controller_context.present? && !controller_context.include?(controller_name)

        distance = (occurrence.created_at.to_f - trace.finished_at.to_f).abs
        [distance, occurrence.error]
      end

      scored.min_by(&:first)&.last
    rescue StandardError
      nil
    end

    def exception_chain(exception)
      chain = []
      current = exception
      depth = 0
      while current && depth < 8
        chain << current
        current = current.cause if current.respond_to?(:cause)
        depth += 1
      end
      chain
    end

    def root_cause(exception)
      exception_chain(exception).last || exception
    end
  end
end
