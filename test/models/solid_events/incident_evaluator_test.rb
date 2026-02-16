# frozen_string_literal: true

require "test_helper"

module SolidEvents
  class IncidentEvaluatorTest < ActiveSupport::TestCase
    test "creates new fingerprint incident" do
      now = Time.current
      trace = SolidEvents::Trace.create!(
        name: "orders.create",
        trace_type: "request",
        source: "OrdersController#create",
        status: "error",
        started_at: now - 10.minutes
      )
      SolidEvents::Summary.create!(
        trace_id: trace.id,
        name: trace.name,
        trace_type: trace.trace_type,
        source: trace.source,
        status: trace.status,
        started_at: now - 10.minutes,
        error_fingerprint: "fp-new",
        event_count: 1,
        record_link_count: 0,
        error_count: 1
      )

      SolidEvents::IncidentEvaluator.evaluate!

      incident = SolidEvents::Incident.where(kind: "new_fingerprint", fingerprint: "fp-new").first
      assert_not_nil incident
      assert_equal "warning", incident.severity
    end

    test "creates error spike incident when threshold exceeded" do
      previous_threshold = SolidEvents.configuration.incident_error_spike_threshold_pct
      previous_min_samples = SolidEvents.configuration.incident_min_samples
      SolidEvents.configuration.incident_error_spike_threshold_pct = 20.0
      SolidEvents.configuration.incident_min_samples = 10

      10.times do |i|
        trace = SolidEvents::Trace.create!(
          name: "payments.capture",
          trace_type: "request",
          source: "PaymentsController#create",
          status: i < 4 ? "error" : "ok",
          started_at: Time.current - 20.minutes
        )
        SolidEvents::Summary.create!(
          trace_id: trace.id,
          name: trace.name,
          trace_type: trace.trace_type,
          source: trace.source,
          status: trace.status,
          started_at: Time.current - 20.minutes,
          duration_ms: 120.0,
          event_count: 1,
          record_link_count: 0,
          error_count: (i < 4 ? 1 : 0)
        )
      end

      SolidEvents::IncidentEvaluator.evaluate!

      incident = SolidEvents::Incident.where(kind: "error_spike", name: "payments.capture").first
      assert_not_nil incident
      assert_equal "critical", incident.severity
    ensure
      SolidEvents.configuration.incident_error_spike_threshold_pct = previous_threshold
      SolidEvents.configuration.incident_min_samples = previous_min_samples
    end
  end
end
