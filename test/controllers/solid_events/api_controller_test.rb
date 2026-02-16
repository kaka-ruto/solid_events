# frozen_string_literal: true

require "test_helper"

module SolidEvents
  class ApiControllerTest < ActionDispatch::IntegrationTest
    test "incidents endpoint returns serialized incidents" do
      incident = SolidEvents::Incident.create!(
        kind: "error_spike",
        severity: "critical",
        status: "active",
        source: "OrdersController#create",
        name: "orders.create",
        payload: {error_rate_pct: 50.0},
        detected_at: Time.current,
        last_seen_at: Time.current
      )

      get "/solid_events/api/incidents", params: {status: "active"}
      assert_response :success
      payload = JSON.parse(@response.body)
      assert_equal incident.id, payload.first["id"]
      assert_equal "error_spike", payload.first["kind"]
    end

    test "trace endpoint returns canonical event and links" do
      trace = SolidEvents::Trace.create!(
        name: "orders.create",
        trace_type: "request",
        source: "OrdersController#create",
        status: "error",
        context: {"request_id" => "req-api"},
        started_at: Time.current
      )
      trace.error_links.create!(solid_error_id: 22)

      get "/solid_events/api/traces/#{trace.id}"
      assert_response :success
      payload = JSON.parse(@response.body)
      assert_equal trace.id, payload["trace"]["trace_id"]
      assert_equal 22, payload["error_links"].first["solid_error_id"]
    end
  end
end
