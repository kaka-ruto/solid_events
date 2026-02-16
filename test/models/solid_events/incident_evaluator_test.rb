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
      assert_equal "active", incident.status
      assert_not_nil incident.last_seen_at
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

    test "suppression rules prevent matching incidents" do
      previous_rules = SolidEvents.configuration.incident_suppression_rules
      SolidEvents.configuration.incident_suppression_rules = [{kind: "new_fingerprint", source: "OrdersController#create"}]

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
        error_fingerprint: "fp-suppressed",
        event_count: 1,
        record_link_count: 0,
        error_count: 1
      )

      SolidEvents::IncidentEvaluator.evaluate!

      incident = SolidEvents::Incident.where(kind: "new_fingerprint", fingerprint: "fp-suppressed").first
      assert_nil incident
    ensure
      SolidEvents.configuration.incident_suppression_rules = previous_rules
    end

    test "notifier is called when new incident is created" do
      previous_notifier = SolidEvents.configuration.incident_notifier
      notifications = []
      SolidEvents.configuration.incident_notifier = ->(incident:, action:) { notifications << [incident.kind, action] }

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
        error_fingerprint: "fp-notify",
        event_count: 1,
        record_link_count: 0,
        error_count: 1
      )

      SolidEvents::IncidentEvaluator.evaluate!

      assert_includes notifications, ["new_fingerprint", :created]
    ensure
      SolidEvents.configuration.incident_notifier = previous_notifier
    end

    test "stale active incidents are auto-resolved" do
      incident = SolidEvents::Incident.create!(
        kind: "error_spike",
        severity: "critical",
        status: "active",
        source: "OrdersController#create",
        name: "orders.create",
        detected_at: 3.hours.ago,
        last_seen_at: 3.hours.ago,
        payload: {error_rate_pct: 30.0}
      )

      SolidEvents::IncidentEvaluator.evaluate!

      assert_equal "resolved", incident.reload.status
      assert_not_nil incident.resolved_at
    end

    test "creates slo burn rate incident when slo budget burns too fast" do
      previous_min_samples = SolidEvents.configuration.incident_min_samples
      previous_target = SolidEvents.configuration.incident_slo_target_error_rate_pct
      previous_burn = SolidEvents.configuration.incident_slo_burn_rate_threshold
      SolidEvents.configuration.incident_min_samples = 5
      SolidEvents.configuration.incident_slo_target_error_rate_pct = 2.0
      SolidEvents.configuration.incident_slo_burn_rate_threshold = 2.0

      6.times do |i|
        status = i < 3 ? "error" : "ok"
        trace = SolidEvents::Trace.create!(
          name: "checkout.create",
          trace_type: "request",
          source: "CheckoutController#create",
          status: status,
          started_at: 30.minutes.ago
        )
        SolidEvents::Summary.create!(
          trace: trace,
          name: trace.name,
          trace_type: trace.trace_type,
          source: trace.source,
          status: status,
          started_at: trace.started_at,
          duration_ms: 120.0,
          event_count: 1,
          record_link_count: 0,
          error_count: (status == "error" ? 1 : 0)
        )
      end

      SolidEvents::IncidentEvaluator.evaluate!
      incident = SolidEvents::Incident.where(kind: "slo_burn_rate", name: "checkout.create").first
      assert_not_nil incident
      assert_equal "critical", incident.severity
      assert_operator incident.payload["burn_rate"], :>=, 2.0
    ensure
      SolidEvents.configuration.incident_min_samples = previous_min_samples
      SolidEvents.configuration.incident_slo_target_error_rate_pct = previous_target
      SolidEvents.configuration.incident_slo_burn_rate_threshold = previous_burn
    end

  end
end
