# frozen_string_literal: true

module SolidEvents
  module Subscribers
    class ControllerSubscriber
      def call(_name, started, finished, _unique_id, payload)
        path = payload[:path].to_s
        return if SolidEvents.ignore_paths.any? { |prefix| path.start_with?(prefix.to_s) }

        controller = payload[:controller].to_s
        action = payload[:action].to_s
        status = payload[:status].to_i
        name = SolidEvents::Labeler.controller_action(controller_name: controller, action_name: action, status: status)

        trace = SolidEvents::Tracer.start_trace!(
          name: name,
          trace_type: "request",
          source: "#{controller}##{action}",
          context: payload.slice(:path, :method, :format, :status)
        )

        SolidEvents::Tracer.record_event!(
          event_type: "controller",
          name: "#{controller}##{action}",
          payload: payload.slice(:path, :method, :format, :status),
          duration_ms: ((finished - started) * 1000.0).round(2)
        )

        if defined?(SolidErrors::Error) && payload[:exception_object]&.respond_to?(:message)
          solid_error = SolidErrors::Error.find_by(message: payload[:exception_object].message)
          SolidEvents::Tracer.link_error!(solid_error.id) if solid_error
        end

        SolidEvents::Tracer.finish_trace!(status: payload[:exception].present? ? "error" : "ok")
        trace
      end
    end
  end
end
