# frozen_string_literal: true
require "digest"
require "json"
require "time"

module SolidEvents
  module Tracer
    module_function

    def start_trace!(name:, trace_type:, source:, context: {}, caused_by_trace_id: nil, caused_by_event_id: nil)
      return unless storage_available?
      context_payload = guarded_payload(
        redact_hash(normalize_context(context)),
        max_bytes: SolidEvents.max_context_payload_bytes
      )

      trace = SolidEvents::Trace.create!(
        name: name,
        trace_type: trace_type,
        source: source,
        caused_by_trace_id: caused_by_trace_id,
        caused_by_event_id: caused_by_event_id,
        context: context_payload,
        started_at: Time.current
      )
      SolidEvents::Current.trace = trace
      SolidEvents::Current.trace_metrics = default_trace_metrics
      create_causal_edge_for_trace!(trace)
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
      final_context = guarded_payload(
        redact_hash(existing_context.merge(extra_context)),
        max_bytes: SolidEvents.max_context_payload_bytes
      )
      trace.update!(status: status, finished_at: Time.current, context: final_context)

      unless keep_trace?(trace, context: final_context)
        trace.destroy!
        SolidEvents::Current.trace = nil
        SolidEvents::Current.trace_metrics = {}
        return nil
      end

      upsert_summary!(trace)
      emit_canonical_log_line!(trace)
      SolidEvents::Current.trace = nil
      SolidEvents::Current.trace_metrics = {}
      trace
    end

    def record_event!(event_type:, name:, payload: {}, duration_ms: nil)
      return unless storage_available?

      trace = current_trace
      return unless trace

      metrics = SolidEvents::Current.trace_metrics
      if metrics.blank?
        metrics = default_trace_metrics
      end
      metrics["event_count"] += 1
      metrics["event_counts"][event_type] = metrics["event_counts"].fetch(event_type, 0) + 1
      if event_type.to_s == "sql"
        metrics["sql_count"] += 1
        metrics["sql_duration_ms"] += duration_ms.to_f
      end
      SolidEvents::Current.trace_metrics = metrics

      created_event = nil
      if !SolidEvents.wide_event_primary? || SolidEvents.persist_sub_events?
        payload_for_event = guarded_payload(
          redact_hash(normalize_context(payload)),
          max_bytes: SolidEvents.max_event_payload_bytes
        )
        created_event = trace.events.create!(
          event_type: event_type,
          name: name,
          payload: payload_for_event,
          duration_ms: duration_ms,
          occurred_at: Time.current
        )
      end
      upsert_summary!(trace)
      created_event
    end

    def annotate!(context = {})
      return unless storage_available?

      trace = current_trace
      return unless trace

      existing_context = normalize_context(trace.context.to_h)
      trace.update!(
        context: guarded_payload(
          redact_hash(existing_context.merge(normalize_context(context))),
          max_bytes: SolidEvents.max_context_payload_bytes
        )
      )
      upsert_summary!(trace)
      trace
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

    def record_state_diff!(record:, action:, before_state:, after_state:)
      return unless storage_available?

      trace = current_trace
      return unless trace
      return if ignored_record_for_linking?(record)

      filtered_before, filtered_after, changed_fields = filtered_state_diff(
        before_state: before_state,
        after_state: after_state
      )
      return if changed_fields.empty?

      record_event!(
        event_type: "state_diff",
        name: "#{record.class.name}##{action}",
        payload: {
          record_type: record.class.name,
          record_id: record.id,
          action: action,
          changed_fields: changed_fields,
          before: filtered_before,
          after: filtered_after
        }
      )
    end

    def link_error!(solid_error_id)
      return unless storage_available?

      trace = current_trace
      return unless trace

      attach_error_link!(trace, solid_error_id)
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

    def register_async_causal_link!(job_id:, caused_by_trace_id:, caused_by_event_id:)
      return if job_id.blank? || caused_by_trace_id.blank?

      payload = {
        "trace_id" => caused_by_trace_id.to_i,
        "event_id" => caused_by_event_id&.to_i,
        "recorded_at" => Time.current.to_i
      }
      if defined?(Rails) && Rails.cache
        Rails.cache.write(async_causal_key(job_id), payload, expires_in: 6.hours)
      else
        @async_causal_memory ||= {}
        @async_causal_memory[job_id.to_s] = payload
      end
      payload
    rescue StandardError
      nil
    end

    def consume_async_causal_link(job_id:)
      return {} if job_id.blank?

      value = if defined?(Rails) && Rails.cache
        key = async_causal_key(job_id)
        payload = Rails.cache.read(key)
        Rails.cache.delete(key)
        payload
      else
        @async_causal_memory ||= {}
        @async_causal_memory.delete(job_id.to_s)
      end
      value.to_h.symbolize_keys
    rescue StandardError
      {}
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
          attach_error_link!(trace, by_fingerprint.id)
          return by_fingerprint
        end
      end

      candidates = error_candidates_from(exception: exception, trace: trace)
      if candidates.empty?
        by_occurrence = find_solid_error_by_occurrence(trace)
        if by_occurrence
          attach_error_link!(trace, by_occurrence.id)
          return by_occurrence
        end
        return
      end

      attempts.times do |attempt|
        solid_error = find_matching_solid_error(candidates: candidates, trace: trace)

        if solid_error
          attach_error_link!(trace, solid_error.id)
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

    def attach_error_link!(trace, solid_error_id)
      return unless trace && solid_error_id

      trace.error_links.find_or_create_by!(solid_error_id: solid_error_id)
      upsert_summary!(trace)
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
      return true if @summary_storage_available

      available = begin
        SolidEvents::Summary.connection.data_source_exists?(SolidEvents::Summary.table_name)
      rescue StandardError
        false
      end

      @summary_storage_available = true if available
      available
    end

    def upsert_summary!(trace)
      return unless trace
      return unless summary_storage_available?

      context = trace.context.to_h
      entity = extract_primary_entity(trace)
      http_status = context["status"].presence&.to_i

      summary = SolidEvents::Summary.find_or_initialize_by(trace_id: trace.id)
      metrics = aggregate_metrics_for(trace)
      feature_slices = extract_feature_slices(context)
      summary.assign_attributes(
        name: trace.name,
        trace_type: trace.trace_type,
        source: trace.source,
        status: trace.status,
        caused_by_trace_id: trace.caused_by_trace_id,
        caused_by_event_id: trace.caused_by_event_id,
        outcome: trace.status == "error" ? "failure" : "success",
        entity_type: entity[:type],
        entity_id: entity[:id],
        http_status: http_status,
        request_method: context["method"],
        request_id: context["request_id"],
        path: context["path"],
        job_class: trace.trace_type == "job" ? trace.source : nil,
        queue_name: context["queue"],
        schema_version: SolidEvents.canonical_schema_version,
        service_name: context["service_name"],
        environment_name: context["environment_name"],
        service_version: context["service_version"],
        deployment_id: context["deployment_id"],
        region: context["region"],
        started_at: trace.started_at,
        finished_at: trace.finished_at,
        duration_ms: trace.finished_at && trace.started_at ? ((trace.finished_at - trace.started_at) * 1000.0).round(2) : nil,
        event_count: metrics[:event_count],
        sql_count: metrics[:sql_count],
        sql_duration_ms: metrics[:sql_duration_ms],
        record_link_count: trace.record_links.count,
        error_count: trace.error_links.count,
        user_id: context["user_id"],
        account_id: context["account_id"],
        error_fingerprint: context["error_fingerprint"],
        payload: {
          event_counts: metrics[:event_counts],
          error_link_ids: trace.error_links.pluck(:solid_error_id),
          context: context,
          feature_slices: feature_slices
        }
      )
      summary.save!
      materialize_journey!(summary)
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

    def extract_feature_slices(context)
      SolidEvents.feature_slice_keys.each_with_object({}) do |key, memo|
        value = context[key]
        memo[key] = value.to_s if value.present?
      end
    rescue StandardError
      {}
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

    def materialize_journey!(summary)
      return unless defined?(SolidEvents::Journey)
      return unless SolidEvents::Journey.connection.data_source_exists?(SolidEvents::Journey.table_name)

      SolidEvents::Journey.materialize_from_summary!(summary)
    rescue StandardError
      nil
    end

    def create_causal_edge_for_trace!(trace)
      return unless trace.caused_by_trace_id.present? || trace.caused_by_event_id.present?
      return unless defined?(SolidEvents::CausalEdge)
      return unless SolidEvents::CausalEdge.connection.data_source_exists?(SolidEvents::CausalEdge.table_name)

      SolidEvents::CausalEdge.find_or_create_by!(
        from_trace_id: trace.caused_by_trace_id,
        from_event_id: trace.caused_by_event_id,
        to_trace_id: trace.id,
        edge_type: "caused_by"
      ) do |edge|
        edge.to_event_id = nil
        edge.occurred_at = trace.started_at || Time.current
        edge.payload = {trace_type: trace.trace_type}
      end
    rescue StandardError
      nil
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

    def ignored_record_for_linking?(record)
      return true if record.is_a?(SolidEvents::Record)
      return true if SolidEvents.ignore_models.include?(record.class.name)
      return true if SolidEvents.ignore_model_prefixes.any? { |prefix| record.class.name.start_with?(prefix.to_s) }
      return true unless track_state_diff_for_record?(record)

      false
    end

    def track_state_diff_for_record?(record)
      type = record.class.name.to_s
      return false if SolidEvents.state_diff_blocklist.include?(type)

      allowlist = SolidEvents.state_diff_allowlist
      return true if allowlist.empty?

      allowlist.include?(type)
    end

    def filtered_state_diff(before_state:, after_state:)
      before_hash = normalize_context(before_state)
      after_hash = normalize_context(after_state)
      ignored_keys = %w[created_at updated_at]
      changed_fields = (before_hash.keys | after_hash.keys).reject { |key| ignored_keys.include?(key) }.select do |key|
        before_hash[key] != after_hash[key]
      end.first(SolidEvents.state_diff_max_changed_fields)
      filtered_before = before_hash.slice(*changed_fields)
      filtered_after = after_hash.slice(*changed_fields)
      [filtered_before, filtered_after, changed_fields]
    end

    def default_trace_metrics
      {
        "event_count" => 0,
        "sql_count" => 0,
        "sql_duration_ms" => 0.0,
        "event_counts" => {}
      }
    end

    def aggregate_metrics_for(trace)
      current = SolidEvents::Current.trace
      metrics = SolidEvents::Current.trace_metrics
      if current && current.id == trace.id && metrics.present?
        return {
          event_count: metrics["event_count"].to_i,
          sql_count: metrics["sql_count"].to_i,
          sql_duration_ms: metrics["sql_duration_ms"].to_f.round(2),
          event_counts: metrics["event_counts"].to_h
        }
      end

      sql_scope = trace.events.where(event_type: "sql")
      {
        event_count: trace.events.count,
        sql_count: sql_scope.count,
        sql_duration_ms: sql_scope.sum(:duration_ms).to_f.round(2),
        event_counts: trace.events.group(:event_type).count
      }
    end

    def redact_hash(value, path: [])
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), output|
          key_string = key.to_s
          current_path = path + [key_string]
          custom_replacement = redaction_replacement_for_path(current_path)
          if custom_replacement
            output[key_string] = custom_replacement
          elsif sensitive_key?(key_string)
            output[key_string] = SolidEvents.redaction_placeholder
          else
            output[key_string] = redact_hash(nested, path: current_path)
          end
        end
      when Array
        value.map.with_index { |entry, index| redact_hash(entry, path: path + [index.to_s]) }
      else
        value
      end
    end

    def redaction_replacement_for_path(path_segments)
      replacement = SolidEvents.redaction_paths[path_segments.join(".")]
      return nil if replacement.nil?
      return SolidEvents.redaction_placeholder if replacement == true

      replacement.to_s
    end

    def guarded_payload(value, max_bytes:)
      serialized = JSON.generate(value)
      return value if serialized.bytesize <= max_bytes

      {
        "_truncated" => true,
        "_original_bytes" => serialized.bytesize,
        "_max_bytes" => max_bytes,
        "_value" => SolidEvents.payload_truncation_placeholder
      }
    rescue StandardError
      value
    end

    def async_causal_key(job_id)
      "solid_events:causal:job:#{job_id}"
    end

    def sensitive_key?(key)
      SolidEvents.sensitive_keys.any? { |sensitive| key.downcase.include?(sensitive.downcase) }
    end
  end
end
