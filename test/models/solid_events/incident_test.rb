# frozen_string_literal: true

require "test_helper"

module SolidEvents
  class IncidentTest < ActiveSupport::TestCase
    test "lifecycle transitions create explicit incident events including reopen" do
      incident = SolidEvents::Incident.create!(
        kind: "error_spike",
        severity: "critical",
        status: "active",
        source: "CheckoutController#create",
        name: "checkout.create",
        payload: {},
        detected_at: Time.current,
        last_seen_at: Time.current
      )

      incident.record_event!(action: "detected")
      incident.acknowledge!
      incident.resolve!
      incident.reopen!

      actions = incident.incident_events.order(:occurred_at).pluck(:action)
      assert_includes actions, "detected"
      assert_includes actions, "acknowledged"
      assert_includes actions, "resolved"
      assert_includes actions, "reopened"
    end
  end
end
