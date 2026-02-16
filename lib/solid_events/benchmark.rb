# frozen_string_literal: true

module SolidEvents
  class Benchmark
    def self.run(sample_size: 200)
      sample_size = sample_size.to_i
      sample_size = 1 if sample_size <= 0

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      traces = SolidEvents::Trace.order(id: :desc).limit(sample_size).to_a
      summaries = SolidEvents::Summary.order(id: :desc).limit(sample_size).to_a
      incidents = SolidEvents::Incident.order(id: :desc).limit(sample_size).to_a
      finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      {
        sample_size: sample_size,
        traces_count: traces.size,
        summaries_count: summaries.size,
        incidents_count: incidents.size,
        elapsed_ms: ((finished - started) * 1000.0).round(2),
        generated_at: Time.current.iso8601
      }
    end

    def self.evaluate(result:, warn_ms:, fail_ms:)
      elapsed = result[:elapsed_ms].to_f
      status = if elapsed > fail_ms.to_f
        "fail"
      elsif elapsed > warn_ms.to_f
        "warn"
      else
        "pass"
      end

      {
        status: status,
        elapsed_ms: elapsed,
        warn_ms: warn_ms.to_f,
        fail_ms: fail_ms.to_f
      }
    end
  end
end
