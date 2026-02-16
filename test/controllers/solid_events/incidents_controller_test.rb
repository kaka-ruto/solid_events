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

    test "events page lists lifecycle events with filtering" do
      incident = SolidEvents::Incident.create!(
        kind: "error_spike",
        severity: "critical",
        status: "active",
        source: "OrdersController#create",
        name: "orders.create",
        payload: {},
        detected_at: Time.current,
        last_seen_at: Time.current
      )
      incident.record_event!(action: "detected")
      incident.acknowledge!

      get "/solid_events/incidents/#{incident.id}/events"
      assert_response :success
      assert_includes @response.body, "Incident ##{incident.id} Events"
      assert_includes @response.body, "acknowledged"

      get "/solid_events/incidents/#{incident.id}/events", params: {event_action: "detected"}
      assert_response :success
      assert_includes @response.body, "detected"
    end
  end
end
