# frozen_string_literal: true

module SolidEvents
  module Subscribers
    class ExternalHttpSubscriber
      def call(name, started, finished, _unique_id, payload)
        method = payload[:method].to_s.upcase.presence || payload[:http_method].to_s.upcase.presence || "GET"
        url = payload[:url].presence || payload[:uri].to_s.presence || payload[:host].presence || "external"
        status = payload[:status] || payload[:status_code]
        duration_ms = ((finished - started) * 1000.0).round(2)
        event_payload = {
          method: method,
          url: url,
          status: status,
          adapter_event: name
        }.compact

        if SolidEvents::Tracer.current_trace
          SolidEvents::Tracer.record_event!(
            event_type: "external_http",
            name: "#{method} #{url}",
            payload: event_payload,
            duration_ms: duration_ms
          )
          return
        end

        source = payload[:client].presence || name.to_s
        SolidEvents::Tracer.start_trace!(
          name: "external_http.#{method.downcase}",
          trace_type: "external_http",
          source: source,
          context: {
            method: method,
            url: url,
            status: status,
            service_name: SolidEvents.service_name,
            environment_name: SolidEvents.environment_name,
            service_version: SolidEvents.service_version,
            deployment_id: SolidEvents.deployment_id,
            region: SolidEvents.region
          }.compact
        )
        SolidEvents::Tracer.record_event!(
          event_type: "external_http",
          name: "#{method} #{url}",
          payload: event_payload,
          duration_ms: duration_ms
        )
        SolidEvents::Tracer.finish_trace!(status: payload[:exception].present? ? "error" : "ok")
      end
    end
  end
end
