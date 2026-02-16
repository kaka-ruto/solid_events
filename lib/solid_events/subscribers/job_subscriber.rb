# frozen_string_literal: true

module SolidEvents
  module Subscribers
    class JobSubscriber
      def call(_name, started, finished, _unique_id, payload)
        job = payload[:job]
        return unless job

        trace_name = "job.#{job.class.name.underscore}"
        return if SolidEvents.ignore_job_prefixes.any? { |prefix| trace_name.start_with?(prefix.to_s) }

        trace = SolidEvents::Tracer.start_trace!(
          name: trace_name,
          trace_type: "job",
          source: job.class.name,
          context: {job_id: job.job_id, queue: job.queue_name}
        )

        SolidEvents::Tracer.record_event!(
          event_type: "job",
          name: job.class.name,
          payload: {job_id: job.job_id, queue: job.queue_name},
          duration_ms: ((finished - started) * 1000.0).round(2)
        )

        SolidEvents::Tracer.finish_trace!(status: payload[:exception_object].present? ? "error" : "ok")
        trace
      end
    end
  end
end
