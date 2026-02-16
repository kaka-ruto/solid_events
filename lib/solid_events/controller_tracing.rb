# frozen_string_literal: true

module SolidEvents
  module ControllerTracing
    extend ActiveSupport::Concern

    included do
      around_action :solid_events_trace_request
    end

    private

    def solid_events_trace_request
      SolidEvents::Tracer.reconcile_recent_error_links!

      request_path = request.path.to_s
      return yield if SolidEvents.ignore_paths.any? { |prefix| request_path.start_with?(prefix.to_s) }
      controller_name = self.class.name.to_s
      return yield if SolidEvents.ignore_controller_prefixes.any? { |prefix| controller_name.start_with?(prefix.to_s) }

      traced = false
      controller = controller_name
      action = action_name.to_s
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      trace_name = SolidEvents::Labeler.controller_action(
        controller_name: controller,
        action_name: action,
        status: nil
      )

      trace_context = {
        "path" => request.path,
        "method" => request.request_method,
        "request_id" => request.request_id,
        "format" => request.format&.to_s,
        "service_name" => SolidEvents.service_name,
        "environment_name" => SolidEvents.environment_name,
        "service_version" => SolidEvents.service_version,
        "deployment_id" => SolidEvents.deployment_id,
        "region" => SolidEvents.region
      }.merge(SolidEvents::ContextScraper.from_controller(self))

      SolidEvents::Tracer.start_trace!(
        name: trace_name,
        trace_type: "request",
        source: "#{controller}##{action}",
        context: trace_context
      )
      traced = true

      exception = nil
      yield
    rescue StandardError => e
      exception = e
      SolidEvents::Tracer.bind_exception_to_trace!(exception)
      raise
    ensure
      return unless traced

      status_code = response&.status
      finished_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      duration_ms = ((finished_at - started_at) * 1000.0).round(2)

      event_payload = {
        "path" => request.path,
        "method" => request.request_method,
        "request_id" => request.request_id,
        "format" => request.format&.to_s,
        "status" => status_code
      }.merge(SolidEvents::ContextScraper.from_controller(self))
      if exception
        event_payload["error_fingerprint"] = SolidEvents::Tracer.error_fingerprint_for(
          exception,
          severity: :error,
          source: "application.action_dispatch"
        )
      end

      SolidEvents::Tracer.record_event!(
        event_type: "controller",
        name: "#{controller}##{action}",
        payload: event_payload,
        duration_ms: duration_ms
      )

      trace = SolidEvents::Tracer.finish_trace!(
        status: exception ? "error" : "ok",
        context: event_payload
      )
      SolidEvents::Tracer.reconcile_error_link_for_trace!(trace, exception: exception) if exception
    end
  end
end
