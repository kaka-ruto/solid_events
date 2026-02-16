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
      assert_equal incident.id, payload["data"].first["id"]
      assert_equal "error_spike", payload["data"].first["kind"]
      assert_equal incident.id, payload["next_cursor"]
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

    test "incidents endpoint supports cursor pagination" do
      older = SolidEvents::Incident.create!(
        kind: "error_spike",
        severity: "critical",
        status: "active",
        source: "OrdersController#create",
        name: "orders.create",
        payload: {},
        detected_at: 1.minute.ago,
        last_seen_at: 1.minute.ago
      )
      newer = SolidEvents::Incident.create!(
        kind: "error_spike",
        severity: "critical",
        status: "active",
        source: "CheckoutController#create",
        name: "checkout.create",
        payload: {},
        detected_at: Time.current,
        last_seen_at: Time.current
      )

      get "/solid_events/api/incidents", params: {limit: 1}
      payload = JSON.parse(@response.body)
      first_id = payload.fetch("data").first.fetch("id")

      get "/solid_events/api/incidents", params: {limit: 10, cursor: first_id}
      second_payload = JSON.parse(@response.body)
      ids = second_payload.fetch("data").map { |row| row.fetch("id") }
      assert_includes ids, older.id
      refute_includes ids, newer.id
    end

    test "traces endpoint supports cursor pagination" do
      older = SolidEvents::Trace.create!(
        name: "orders.create",
        trace_type: "request",
        source: "OrdersController#create",
        status: "ok",
        started_at: 5.minutes.ago
      )
      newer = SolidEvents::Trace.create!(
        name: "checkout.create",
        trace_type: "request",
        source: "CheckoutController#create",
        status: "ok",
        started_at: Time.current
      )

      get "/solid_events/api/traces", params: {limit: 1}
      payload = JSON.parse(@response.body)
      first_id = payload.fetch("data").first.fetch("trace_id")

      get "/solid_events/api/traces", params: {limit: 10, cursor: first_id}
      second_payload = JSON.parse(@response.body)
      ids = second_payload.fetch("data").map { |row| row.fetch("trace_id") }
      assert_includes ids, older.id
      refute_includes ids, newer.id
    end

    test "traces endpoint can filter by configured feature slice" do
      create_summary_for_metrics(source: "CheckoutController#create", context: {"feature_flag" => "checkout_v2"})
      create_summary_for_metrics(source: "OrdersController#create", context: {"feature_flag" => "orders_v1"})

      get "/solid_events/api/traces", params: {feature_key: "feature_flag", feature_value: "checkout_v2"}
      assert_response :success
      payload = JSON.parse(@response.body)
      data = payload.fetch("data")
      assert_equal 1, data.size
      assert_equal "CheckoutController#create", data.first["source"]
    end

    test "metrics endpoints can filter by configured feature slice" do
      create_summary_for_metrics(source: "CheckoutController#create", status: "error", context: {"feature_flag" => "checkout_v2"})
      create_summary_for_metrics(source: "CheckoutController#create", status: "ok", context: {"feature_flag" => "checkout_v2"})
      create_summary_for_metrics(source: "CheckoutController#create", status: "ok", context: {"feature_flag" => "checkout_v1"})

      get "/solid_events/api/metrics/error_rates", params: {dimension: "source", feature_key: "feature_flag", feature_value: "checkout_v2"}
      assert_response :success
      payload = JSON.parse(@response.body)
      group = payload.fetch("groups").find { |row| row["value"] == "CheckoutController#create" }
      assert_equal 50.0, group["error_rate_pct"]
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

    test "error rates endpoint returns grouped error rates" do
      create_summary_for_metrics(source: "CheckoutController#create", status: "ok")
      create_summary_for_metrics(source: "CheckoutController#create", status: "error")
      create_summary_for_metrics(source: "OrdersController#create", status: "ok")

      get "/solid_events/api/metrics/error_rates", params: {dimension: "source", window: "24h"}
      assert_response :success

      payload = JSON.parse(@response.body)
      checkout = payload.fetch("groups").find { |group| group["value"] == "CheckoutController#create" }
      orders = payload.fetch("groups").find { |group| group["value"] == "OrdersController#create" }

      assert_equal "source", payload["dimension"]
      assert_equal 2, checkout["total_count"]
      assert_equal 1, checkout["error_count"]
      assert_equal 50.0, checkout["error_rate_pct"]
      assert_equal 0.0, orders["error_rate_pct"]
    end

    test "latency endpoint returns grouped latency aggregates" do
      create_summary_for_metrics(source: "CheckoutController#create", duration_ms: 100.0)
      create_summary_for_metrics(source: "CheckoutController#create", duration_ms: 300.0)
      create_summary_for_metrics(source: "OrdersController#create", duration_ms: 50.0)

      get "/solid_events/api/metrics/latency", params: {dimension: "source", window: "24h"}
      assert_response :success

      payload = JSON.parse(@response.body)
      checkout = payload.fetch("groups").find { |group| group["value"] == "CheckoutController#create" }

      assert_equal "source", payload["dimension"]
      assert_equal 2, checkout["sample_count"]
      assert_equal 200.0, checkout["avg_duration_ms"]
      assert_equal 300.0, checkout["max_duration_ms"]
    end

    test "compare metrics endpoint returns error rate deltas between windows" do
      create_summary_for_metrics(source: "CheckoutController#create", status: "error", started_at: 2.hours.ago)
      create_summary_for_metrics(source: "CheckoutController#create", status: "ok", started_at: 2.hours.ago)

      create_summary_for_metrics(source: "CheckoutController#create", status: "error", started_at: 26.hours.ago)
      create_summary_for_metrics(source: "CheckoutController#create", status: "ok", started_at: 26.hours.ago)
      create_summary_for_metrics(source: "CheckoutController#create", status: "ok", started_at: 26.hours.ago)
      create_summary_for_metrics(source: "CheckoutController#create", status: "ok", started_at: 26.hours.ago)

      get "/solid_events/api/metrics/compare", params: {dimension: "source", metric: "error_rate", window: "24h"}
      assert_response :success

      payload = JSON.parse(@response.body)
      checkout = payload.fetch("groups").find { |group| group["value"] == "CheckoutController#create" }

      assert_equal "error_rate", payload["metric"]
      assert_equal 50.0, checkout["current"]
      assert_equal 25.0, checkout["baseline"]
      assert_equal 25.0, checkout["delta"]
      assert_equal 100.0, checkout["delta_pct"]
    end

    test "compare metrics endpoint returns latency deltas between windows" do
      create_summary_for_metrics(source: "CheckoutController#create", duration_ms: 400.0, started_at: 2.hours.ago)
      create_summary_for_metrics(source: "CheckoutController#create", duration_ms: 200.0, started_at: 2.hours.ago)
      create_summary_for_metrics(source: "CheckoutController#create", duration_ms: 100.0, started_at: 26.hours.ago)
      create_summary_for_metrics(source: "CheckoutController#create", duration_ms: 100.0, started_at: 26.hours.ago)

      get "/solid_events/api/metrics/compare", params: {dimension: "source", metric: "latency_avg", window: "24h"}
      assert_response :success

      payload = JSON.parse(@response.body)
      checkout = payload.fetch("groups").find { |group| group["value"] == "CheckoutController#create" }

      assert_equal "latency_avg", payload["metric"]
      assert_equal 300.0, checkout["current"]
      assert_equal 100.0, checkout["baseline"]
      assert_equal 200.0, checkout["delta"]
      assert_equal 200.0, checkout["delta_pct"]
    end

    test "cohort metrics endpoint returns grouped cohort values" do
      create_summary_for_metrics(source: "CheckoutController#create", status: "error", context: {"plan" => "premium"})
      create_summary_for_metrics(source: "CheckoutController#create", status: "ok", context: {"plan" => "premium"})
      create_summary_for_metrics(source: "CheckoutController#create", status: "ok", context: {"plan" => "free"})

      get "/solid_events/api/metrics/cohorts", params: {cohort_key: "plan", metric: "error_rate", window: "24h"}
      assert_response :success

      payload = JSON.parse(@response.body)
      premium = payload.fetch("groups").find { |group| group["cohort_value"] == "premium" }
      free = payload.fetch("groups").find { |group| group["cohort_value"] == "free" }

      assert_equal "plan", payload["cohort_key"]
      assert_equal "error_rate", payload["metric"]
      assert_equal 50.0, premium["value"]
      assert_equal 0.0, free["value"]
    end

    test "cohort metrics endpoint requires cohort key" do
      get "/solid_events/api/metrics/cohorts", params: {metric: "error_rate"}
      assert_response :unprocessable_entity
      payload = JSON.parse(@response.body)
      assert_equal "cohort_key is required", payload["error"]
    end

    test "journeys endpoint groups traces by request id" do
      request_id = "req-journey-1"
      create_summary_for_metrics(
        source: "CheckoutController#create",
        status: "ok",
        started_at: 10.minutes.ago,
        request_id: request_id
      )
      create_summary_for_metrics(
        source: "PaymentsController#create",
        status: "error",
        started_at: 9.minutes.ago,
        request_id: request_id
      )

      get "/solid_events/api/journeys", params: {request_id: request_id, window: "24h"}
      assert_response :success

      payload = JSON.parse(@response.body)
      journey = payload.fetch("journeys").first
      assert_equal "request:#{request_id}", journey["journey_key"]
      assert_equal 2, journey["trace_count"]
      assert_equal 1, journey["error_count"]
      assert_equal request_id, journey["request_id"]
      assert_equal 2, journey.fetch("traces").size
    end

    test "journeys endpoint groups traces by entity when request id is absent" do
      create_summary_for_metrics(
        source: "OrdersController#create",
        status: "ok",
        started_at: 8.minutes.ago,
        entity_type: "Order",
        entity_id: 99
      )
      create_summary_for_metrics(
        source: "OrdersController#update",
        status: "error",
        started_at: 7.minutes.ago,
        entity_type: "Order",
        entity_id: 99
      )

      get "/solid_events/api/journeys", params: {entity_type: "Order", entity_id: 99, window: "24h"}
      assert_response :success
      payload = JSON.parse(@response.body)
      journey = payload.fetch("journeys").first
      assert_equal "entity:Order:99", journey["journey_key"]
      assert_equal 2, journey["trace_count"]
      assert_equal 1, journey["error_count"]
    end

    test "journeys endpoint supports errors only filter" do
      request_id = "req-errors-only"
      create_summary_for_metrics(
        source: "CheckoutController#create",
        status: "ok",
        started_at: 10.minutes.ago,
        request_id: request_id
      )
      create_summary_for_metrics(
        source: "PaymentsController#create",
        status: "error",
        started_at: 9.minutes.ago,
        request_id: request_id
      )

      get "/solid_events/api/journeys", params: {request_id: request_id, window: "24h", errors_only: true}
      assert_response :success
      payload = JSON.parse(@response.body)
      journey = payload.fetch("journeys").first
      assert_equal true, payload["errors_only"]
      assert_equal 1, journey["trace_count"]
      assert_equal 1, journey["error_count"]
    end

    private

    def create_summary_for_metrics(source:, status: "ok", duration_ms: 120.0, started_at: 5.minutes.ago, context: {}, request_id: nil, entity_type: nil, entity_id: nil)
      trace = SolidEvents::Trace.create!(
        name: source.underscore.tr("#", "."),
        trace_type: "request",
        source: source,
        status: status,
        started_at: started_at
      )

      SolidEvents::Summary.create!(
        trace: trace,
        name: trace.name,
        trace_type: trace.trace_type,
        source: source,
        status: status,
        request_id: request_id,
        entity_type: entity_type,
        entity_id: entity_id,
        started_at: started_at,
        finished_at: started_at + 1.minute,
        duration_ms: duration_ms,
        payload: {"context" => context}
      )
    end
  end
end
