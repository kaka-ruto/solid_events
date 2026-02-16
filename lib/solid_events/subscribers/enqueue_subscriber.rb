# frozen_string_literal: true

module SolidEvents
  module Subscribers
    class EnqueueSubscriber
      def call(_name, started, finished, _unique_id, payload)
        trace = SolidEvents::Tracer.current_trace
        job = payload[:job]
        return unless trace
        return unless job

        duration_ms = ((finished - started) * 1000.0).round(2)
        event = SolidEvents::Tracer.record_event!(
          event_type: "job_enqueue",
          name: job.class.name,
          payload: {
            job_id: job.job_id,
            queue: job.queue_name
          },
          duration_ms: duration_ms
        )
        SolidEvents::Tracer.register_async_causal_link!(
          job_id: job.job_id,
          caused_by_trace_id: trace.id,
          caused_by_event_id: event&.id
        )
      end
    end
  end
end
