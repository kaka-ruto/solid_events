# frozen_string_literal: true
require "set"

module SolidEvents
  class IncidentEvaluator
    class << self
      def evaluate!
        return unless incident_storage_available?
        detect_new_fingerprints!
        detect_error_spikes!
        detect_p95_regressions!
      rescue StandardError
        nil
      end

      private

      def incident_storage_available?
        SolidEvents::Incident.connection.data_source_exists?(SolidEvents::Incident.table_name)
      rescue StandardError
        false
      end

      def detect_new_fingerprints!
        recent = SolidEvents::Summary
          .where(started_at: 1.hour.ago..Time.current)
          .where.not(error_fingerprint: [nil, ""])
          .order(started_at: :desc)

        historical = SolidEvents::Summary
          .where(started_at: 14.days.ago...1.hour.ago)
          .where.not(error_fingerprint: [nil, ""])
          .distinct
          .pluck(:error_fingerprint)
          .to_set

        recent.each do |summary|
          next if historical.include?(summary.error_fingerprint)

          upsert_incident!(
            kind: "new_fingerprint",
            severity: "warning",
            source: summary.source,
            name: summary.name,
            fingerprint: summary.error_fingerprint,
            payload: {trace_id: summary.trace_id}
          )
        end
      end

      def detect_error_spikes!
        grouped = grouped_recent_summaries
        grouped.each do |(name, source), rows|
          next if rows.size < SolidEvents.incident_min_samples

          error_rate = (rows.count { |row| row.status == "error" }.to_f / rows.size) * 100.0
          next unless error_rate >= SolidEvents.incident_error_spike_threshold_pct

          upsert_incident!(
            kind: "error_spike",
            severity: "critical",
            source: source,
            name: name,
            payload: {
              error_rate_pct: error_rate.round(2),
              sample_size: rows.size
            }
          )
        end
      end

      def detect_p95_regressions!
        grouped = grouped_recent_summaries
        grouped.each do |(name, source), rows|
          recent = rows.select { |row| row.started_at >= 1.hour.ago }.map(&:duration_ms).compact.sort
          baseline = SolidEvents::Summary
            .where(name: name, source: source, started_at: 7.days.ago...1.hour.ago)
            .where.not(duration_ms: nil)
            .pluck(:duration_ms)
            .compact
            .sort
          next if recent.size < SolidEvents.incident_min_samples || baseline.size < SolidEvents.incident_min_samples

          recent_p95 = percentile(recent, 0.95)
          baseline_p95 = percentile(baseline, 0.95)
          next unless baseline_p95.positive?
          next unless recent_p95 >= (baseline_p95 * SolidEvents.incident_p95_regression_factor)

          upsert_incident!(
            kind: "p95_regression",
            severity: "warning",
            source: source,
            name: name,
            payload: {
              recent_p95_ms: recent_p95,
              baseline_p95_ms: baseline_p95,
              factor: (recent_p95 / baseline_p95).round(2)
            }
          )
        end
      end

      def grouped_recent_summaries
        summaries = SolidEvents::Summary.where(started_at: 24.hours.ago..Time.current)
        summaries.group_by { |summary| [summary.name, summary.source] }
      end

      def percentile(sorted_values, ratio)
        return 0.0 if sorted_values.empty?

        index = (ratio * (sorted_values.length - 1)).ceil
        sorted_values[index].to_f.round(2)
      end

      def upsert_incident!(kind:, severity:, source:, name:, fingerprint: nil, payload:)
        existing = SolidEvents::Incident.where(
          kind: kind,
          source: source,
          name: name,
          fingerprint: fingerprint
        ).where("detected_at >= ?", 1.hour.ago).order(detected_at: :desc).first

        if existing
          existing.update!(payload: payload, detected_at: Time.current, severity: severity)
          return existing
        end

        SolidEvents::Incident.create!(
          kind: kind,
          severity: severity,
          source: source,
          name: name,
          fingerprint: fingerprint,
          payload: payload,
          detected_at: Time.current
        )
      end
    end
  end
end
