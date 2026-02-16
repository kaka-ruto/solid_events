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

    test "incident traces endpoint returns evidence traces" do
      trace = SolidEvents::Trace.create!(
        name: "orders.create",
        trace_type: "request",
        source: "OrdersController#create",
        status: "error",
        started_at: Time.current
      )
      incident = SolidEvents::Incident.create!(
        kind: "error_spike",
        severity: "critical",
        status: "active",
        source: "OrdersController#create",
        name: "orders.create",
        payload: {"trace_ids" => [trace.id]},
        detected_at: Time.current,
        last_seen_at: Time.current
      )

      get "/solid_events/api/incidents/#{incident.id}/traces"
      assert_response :success
      payload = JSON.parse(@response.body)
      assert_equal incident.id, payload["incident"]["id"]
      assert_equal trace.id, payload["traces"].first["trace_id"]
    end

    test "incident lifecycle endpoints update status" do
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

      patch "/solid_events/api/incidents/#{incident.id}/acknowledge"
      assert_response :success
      assert_equal "acknowledged", incident.reload.status

      patch "/solid_events/api/incidents/#{incident.id}/resolve"
      assert_response :success
      assert_equal "resolved", incident.reload.status

      patch "/solid_events/api/incidents/#{incident.id}/reopen"
      assert_response :success
      assert_equal "active", incident.reload.status

      patch "/solid_events/api/incidents/#{incident.id}/assign", params: {owner: "alice", team: "platform", assigned_by: "bot", assignment_note: "primary oncall"}
      assert_response :success
      assert_equal "alice", incident.reload.owner
      assert_equal "platform", incident.reload.team
      assert_equal "bot", incident.assigned_by
      assert_equal "primary oncall", incident.assignment_note
      assert_not_nil incident.assigned_at

      patch "/solid_events/api/incidents/#{incident.id}/mute", params: {minutes: 30}
      assert_response :success
      assert_not_nil incident.reload.muted_until

      patch "/solid_events/api/incidents/#{incident.id}/resolve", params: {resolved_by: "alice", resolution_note: "deployed fix"}
      assert_response :success
      assert_equal "resolved", incident.reload.status
      assert_equal "alice", incident.resolved_by
      assert_equal "deployed fix", incident.resolution_note
    end

    test "incident context returns links and evidence" do
      trace = SolidEvents::Trace.create!(
        name: "orders.create",
        trace_type: "request",
        source: "OrdersController#create",
        status: "error",
        started_at: Time.current
      )
      trace.error_links.create!(solid_error_id: 99)
      incident = SolidEvents::Incident.create!(
        kind: "error_spike",
        severity: "critical",
        status: "active",
        source: "OrdersController#create",
        name: "orders.create",
        payload: {"trace_ids" => [trace.id], "trace_query" => {"name" => "orders.create"}},
        detected_at: Time.current,
        last_seen_at: Time.current
      )

      get "/solid_events/api/incidents/#{incident.id}/context"
      assert_response :success
      payload = JSON.parse(@response.body)
      assert_equal incident.id, payload["incident"]["id"]
      assert_equal 1, payload["evidence"]["trace_count"]
      assert_equal 99, payload["evidence"]["error_ids"].first
      assert payload["links"]["traces_ui"].include?("name=orders.create")
    end

    test "api token is enforced when configured" do
      previous_token = SolidEvents.configuration.api_token
      SolidEvents.configuration.api_token = "secret123"

      get "/solid_events/api/incidents"
      assert_response :unauthorized

      get "/solid_events/api/incidents", headers: {"X-Solid-Events-Token" => "secret123"}
      assert_response :success
    ensure
      SolidEvents.configuration.api_token = previous_token
    end
  end
end
