# frozen_string_literal: true

require "test_helper"

module SolidEvents
  class IncidentsControllerTest < ActionDispatch::IntegrationTest
    test "incident lifecycle actions update status" do
      incident = SolidEvents::Incident.create!(
        kind: "error_spike",
        severity: "critical",
        status: "active",
        source: "OrdersController#create",
        name: "orders.create",
        payload: {error_rate_pct: 34.0},
        detected_at: Time.current,
        last_seen_at: Time.current
      )

      patch "/solid_events/incidents/#{incident.id}/acknowledge"
      assert_response :redirect
      assert_equal "acknowledged", incident.reload.status

      patch "/solid_events/incidents/#{incident.id}/resolve"
      assert_response :redirect
      assert_equal "resolved", incident.reload.status
      assert_not_nil incident.resolved_at

      patch "/solid_events/incidents/#{incident.id}/reopen"
      assert_response :redirect
      assert_equal "active", incident.reload.status
      assert_nil incident.resolved_at
    end
  end
end
