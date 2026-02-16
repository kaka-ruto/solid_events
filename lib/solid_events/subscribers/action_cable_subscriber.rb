# frozen_string_literal: true

module SolidEvents
  module Subscribers
    class ActionCableSubscriber
      def call(_name, started, finished, _unique_id, payload)
        channel_class = payload[:channel_class].presence || payload[:channel].presence || "ActionCable"
        action = payload[:action].presence || "perform"
        duration_ms = ((finished - started) * 1000.0).round(2)
        event_payload = {
          channel_class: channel_class,
          action: action,
          connection_identifier: payload[:connection_identifier]
        }.compact

        if SolidEvents::Tracer.current_trace
          SolidEvents::Tracer.record_event!(
            event_type: "action_cable",
            name: "#{channel_class}##{action}",
            payload: event_payload,
            duration_ms: duration_ms
          )
          return
        end

        SolidEvents::Tracer.start_trace!(
          name: "cable.#{channel_class.to_s.underscore}.#{action}",
          trace_type: "cable",
          source: channel_class.to_s,
          context: {
            service_name: SolidEvents.service_name,
            environment_name: SolidEvents.environment_name,
            service_version: SolidEvents.service_version,
            deployment_id: SolidEvents.deployment_id,
            region: SolidEvents.region
          }
        )
        SolidEvents::Tracer.record_event!(
          event_type: "action_cable",
          name: "#{channel_class}##{action}",
          payload: event_payload,
          duration_ms: duration_ms
        )
        SolidEvents::Tracer.finish_trace!(status: payload[:exception].present? ? "error" : "ok")
      end
    end
  end
end
