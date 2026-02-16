# frozen_string_literal: true

module SolidEvents
  module Subscribers
    class MailerSubscriber
      def call(_name, started, finished, _unique_id, payload)
        mailer = payload[:mailer].presence || "ActionMailer"
        action = payload[:action].presence || "process"
        duration_ms = ((finished - started) * 1000.0).round(2)
        event_payload = {
          mailer: mailer,
          action: action,
          message_id: payload[:message_id],
          subject: payload[:subject]
        }.compact

        if SolidEvents::Tracer.current_trace
          SolidEvents::Tracer.record_event!(
            event_type: "mailer",
            name: "#{mailer}##{action}",
            payload: event_payload,
            duration_ms: duration_ms
          )
          return
        end

        SolidEvents::Tracer.start_trace!(
          name: "mailer.#{mailer.to_s.underscore}.#{action}",
          trace_type: "mailer",
          source: mailer.to_s,
          context: {
            service_name: SolidEvents.service_name,
            environment_name: SolidEvents.environment_name,
            service_version: SolidEvents.service_version,
            deployment_id: SolidEvents.deployment_id,
            region: SolidEvents.region
          }
        )
        SolidEvents::Tracer.record_event!(
          event_type: "mailer",
          name: "#{mailer}##{action}",
          payload: event_payload,
          duration_ms: duration_ms
        )
        SolidEvents::Tracer.finish_trace!(status: payload[:exception].present? ? "error" : "ok")
      end
    end
  end
end
