# frozen_string_literal: true

require "test_helper"

module SolidEvents
  class TracesControllerTest < ActionDispatch::IntegrationTest
    test "index and show" do
      trace = SolidEvents::Trace.create!(name: "order.created", trace_type: "request", source: "OrdersController#create", status: "ok", context: {}, started_at: Time.current)
      trace.events.create!(event_type: "controller", name: "OrdersController#create", payload: {}, occurred_at: Time.current)
      trace.error_links.create!(solid_error_id: 123)
      trace.create_summary!(
        name: trace.name,
        trace_type: trace.trace_type,
        source: trace.source,
        status: trace.status,
        outcome: "success",
        entity_type: "Order",
        entity_id: 987,
        error_fingerprint: "fp-123",
        request_id: "req-123",
        service_name: "anywaye",
        environment_name: "production",
        service_version: "v1",
        deployment_id: "d1",
        region: "us-east-1",
        started_at: trace.started_at,
        event_count: 1,
        record_link_count: 0,
        error_count: 1
      )
      related_trace = SolidEvents::Trace.create!(name: "order.updated", trace_type: "request", source: "OrdersController#update", status: "error", context: {}, started_at: 1.minute.ago)
      related_trace.create_summary!(
        name: related_trace.name,
        trace_type: related_trace.trace_type,
        source: related_trace.source,
        status: related_trace.status,
        outcome: "failure",
        entity_type: "Order",
        entity_id: 987,
        error_fingerprint: "fp-123",
        request_id: "req-123",
        started_at: related_trace.started_at,
        event_count: 1,
        record_link_count: 0,
        error_count: 1
      )
      SolidEvents::Incident.create!(
        kind: "error_spike",
        severity: "critical",
        status: "active",
        source: trace.source,
        name: trace.name,
        payload: {trace_query: {name: trace.name, source: trace.source}},
        detected_at: Time.current,
        last_seen_at: Time.current
      )

      get "/solid_events"
      assert_response :success
      assert_includes @response.body, "Context Graph"
      assert_includes @response.body, "Incidents Feed"
      assert_includes @response.body, "Journey Sequences"
      assert_includes @response.body, "Timeline"
      assert_includes @response.body, "Saved Views"
      assert_includes @response.body, "Actions"
      assert_includes @response.body, "Open traces"
      assert_includes @response.body, "Compare deploy"
      assert_includes @response.body, "Open journey"
      assert_includes @response.body, "Journey API"
      assert_includes @response.body, "Throughput"
      assert_includes @response.body, "Hot Paths"
      assert_includes @response.body, "Regression Candidates"
      assert_includes @response.body, "New Error Fingerprints"
      assert_includes @response.body, "Since Current Deploy/Version"
      assert_includes @response.body, "Compare Metrics"

      get "/solid_events", params: {entity_type: "Order", entity_id: "987"}
      assert_response :success

      get "/solid_events", params: {error_fingerprint: "fp-123"}
      assert_response :success

      get "/solid_events", params: {request_id: "req-123"}
      assert_response :success

      get "/solid_events/#{trace.id}"
      assert_response :success
      assert_includes @response.body, "Trace ##{trace.id}"
      assert_includes @response.body, "Canonical Event"
      assert_includes @response.body, "Summary Dimensions"
      assert_includes @response.body, "Correlation Pivots"
      assert_includes @response.body, "SQL:"
      assert_includes @response.body, "Service: anywaye"
      assert_includes @response.body, "Related Traces by Entity"
      assert_includes @response.body, "Related Traces by Error Fingerprint"
      assert_includes @response.body, "Open all traces for this entity"
      assert_includes @response.body, "Open all traces for this error fingerprint"
      assert_includes @response.body, "Open all traces for this request id"
      assert_includes @response.body, "Journey API (entity)"
      assert_includes @response.body, "Journey API (request)"
      assert_includes @response.body, related_trace.name
      assert_includes @response.body, "/solid_errors/123"

      get "/solid_events/hot_path", params: {name: trace.name, source: trace.source, window: "7d"}
      assert_response :success
      assert_includes @response.body, "Hot Path Drilldown"
      assert_includes @response.body, "Hourly Buckets"

      get "/solid_events/timeline", params: {request_id: "req-123", window: "24h"}
      assert_response :success
      assert_includes @response.body, "Timeline View"
      assert_includes @response.body, "OrdersController#create"
    end

    test "saved views are listed on the traces index" do
      saved_view = SolidEvents::SavedView.create!(
        name: "Checkout errors",
        filters: {"source" => "CheckoutController#create", "status" => "error"}
      )

      get "/solid_events"
      assert_response :success
      assert_includes @response.body, saved_view.name
    end

    test "index compare panel supports custom windows and metrics" do
      now_trace = SolidEvents::Trace.create!(
        name: "checkout.create",
        trace_type: "request",
        source: "CheckoutController#create",
        status: "error",
        started_at: 2.hours.ago
      )
      SolidEvents::Summary.create!(
        trace: now_trace,
        name: now_trace.name,
        trace_type: now_trace.trace_type,
        source: now_trace.source,
        status: "error",
        started_at: 2.hours.ago,
        finished_at: 2.hours.ago + 1.minute,
        duration_ms: 400.0
      )

      baseline_trace = SolidEvents::Trace.create!(
        name: "checkout.create",
        trace_type: "request",
        source: "CheckoutController#create",
        status: "ok",
        started_at: 26.hours.ago
      )
      SolidEvents::Summary.create!(
        trace: baseline_trace,
        name: baseline_trace.name,
        trace_type: baseline_trace.trace_type,
        source: baseline_trace.source,
        status: "ok",
        started_at: 26.hours.ago,
        finished_at: 26.hours.ago + 1.minute,
        duration_ms: 100.0
      )

      get "/solid_events", params: {compare_metric: "latency_avg", compare_window: "24h", compare_baseline_window: "24h", compare_dimension: "source"}
      assert_response :success
      assert_includes @response.body, "Current window"
      assert_includes @response.body, "Baseline window"
      assert_includes @response.body, "CheckoutController#create"
    end

    test "index supports feature slice filters" do
      trace = SolidEvents::Trace.create!(
        name: "checkout.create",
        trace_type: "request",
        source: "CheckoutController#create",
        status: "ok",
        started_at: Time.current
      )
      trace.create_summary!(
        name: trace.name,
        trace_type: trace.trace_type,
        source: trace.source,
        status: trace.status,
        started_at: trace.started_at,
        finished_at: trace.started_at + 1.minute,
        duration_ms: 120.0,
        payload: {"feature_slices" => {"feature_flag" => "checkout_v2"}}
      )

      get "/solid_events", params: {feature_key: "feature_flag", feature_value: "checkout_v2"}
      assert_response :success
      assert_includes @response.body, "checkout_v2"
      assert_includes @response.body, "Feature key"
      assert_includes @response.body, "Feature value"
    end

    test "index journey panel supports request and entity grouping" do
      request_trace = SolidEvents::Trace.create!(
        name: "checkout.create",
        trace_type: "request",
        source: "CheckoutController#create",
        status: "error",
        started_at: 2.minutes.ago
      )
      request_trace.create_summary!(
        name: request_trace.name,
        trace_type: request_trace.trace_type,
        source: request_trace.source,
        status: request_trace.status,
        request_id: "req-journey-1",
        started_at: request_trace.started_at,
        finished_at: request_trace.started_at + 1.minute
      )

      entity_trace = SolidEvents::Trace.create!(
        name: "order.update",
        trace_type: "request",
        source: "OrdersController#update",
        status: "ok",
        started_at: 1.minute.ago
      )
      entity_trace.create_summary!(
        name: entity_trace.name,
        trace_type: entity_trace.trace_type,
        source: entity_trace.source,
        status: entity_trace.status,
        entity_type: "Order",
        entity_id: 123,
        started_at: entity_trace.started_at,
        finished_at: entity_trace.started_at + 1.minute
      )

      get "/solid_events", params: {journey_group_by: "request", journey_limit: 10}
      assert_response :success
      assert_includes @response.body, "request:req-journey-1"

      get "/solid_events", params: {journey_group_by: "entity", journey_limit: 10}
      assert_response :success
      assert_includes @response.body, "entity:Order:123"
    end

    test "can disable request-time incident evaluation" do
      previous = SolidEvents.configuration.evaluate_incidents_on_request
      SolidEvents.configuration.evaluate_incidents_on_request = false

      trace = SolidEvents::Trace.create!(
        name: "orders.create",
        trace_type: "request",
        source: "OrdersController#create",
        status: "error",
        started_at: Time.current
      )
      SolidEvents::Summary.create!(
        trace_id: trace.id,
        name: trace.name,
        trace_type: trace.trace_type,
        source: trace.source,
        status: trace.status,
        started_at: trace.started_at,
        error_fingerprint: "fp-no-eval",
        event_count: 1,
        record_link_count: 0,
        error_count: 1
      )

      get "/solid_events"
      assert_response :success
      assert_equal 0, SolidEvents::Incident.count
    ensure
      SolidEvents.configuration.evaluate_incidents_on_request = previous
    end
  end
end
