# frozen_string_literal: true

require "digest"

module SolidEvents
  module Subscribers
    class ErrorSubscriber
      def report(error, handled:, severity:, context:, source: nil)
        return unless defined?(SolidErrors::Error)

        trace = SolidEvents::Tracer.current_trace || SolidEvents::Tracer.consume_bound_trace_for_exception(error)
        return unless trace

        fingerprint = error_fingerprint(error, severity: severity, source: source)
        persist_fingerprint(trace, fingerprint)
        solid_error = find_solid_error_by_fingerprint(fingerprint)
        solid_error ||= find_solid_error_by_exception(error, trace: trace)

        return unless solid_error

        trace.error_links.find_or_create_by!(solid_error_id: solid_error.id)
      rescue StandardError
        nil
      end

      private

      def error_fingerprint(error, severity:, source:)
        sanitized_message = if defined?(SolidErrors::Sanitizer)
          SolidErrors::Sanitizer.sanitize(error.message)
        else
          error.message.to_s
        end

        Digest::SHA256.hexdigest([error.class.name, sanitized_message, severity, source].join)
      end

      def find_solid_error_by_fingerprint(fingerprint)
        10.times do |attempt|
          solid_error = SolidErrors::Error.find_by(fingerprint: fingerprint)
          return solid_error if solid_error

          sleep(0.05 * (attempt + 1))
        end

        nil
      end

      def find_solid_error_by_exception(error, trace:)
        candidates = exception_chain(error).map do |candidate|
          [candidate.class.name, sanitize_message(candidate.message)]
        end.uniq

        candidates.each do |exception_class, message|
          if defined?(SolidErrors::Occurrence)
            scope = SolidErrors::Error
              .joins(:occurrences)
              .where(exception_class: exception_class, message: message)
            if trace.finished_at
              scope = scope.where(solid_errors_occurrences: {created_at: (trace.started_at - 5.minutes)..(trace.finished_at + 5.minutes)})
            end
            match = scope.order("solid_errors_occurrences.created_at DESC").first
          else
            scope = SolidErrors::Error.where(exception_class: exception_class, message: message)
            if trace.finished_at
              scope = scope.where(updated_at: (trace.started_at - 5.minutes)..(trace.finished_at + 5.minutes))
            end
            match = scope.order(updated_at: :desc).first
          end

          return match if match
        end

        nil
      end

      def sanitize_message(message)
        if defined?(SolidErrors::Sanitizer)
          SolidErrors::Sanitizer.sanitize(message)
        else
          message.to_s
        end
      end

      def persist_fingerprint(trace, fingerprint)
        context = trace.context.to_h
        return if context["error_fingerprint"] == fingerprint

        trace.update!(context: context.merge("error_fingerprint" => fingerprint))
      rescue StandardError
        nil
      end

      def exception_chain(error)
        chain = []
        current = error
        depth = 0
        while current && depth < 8
          chain << current
          current = current.cause if current.respond_to?(:cause)
          depth += 1
        end
        chain
      end
    end
  end
end
