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
      assert_includes @response.body, "Actions"
      assert_includes @response.body, "Open traces"
      assert_includes @response.body, "Throughput"
      assert_includes @response.body, "Hot Paths"
      assert_includes @response.body, "Regression Candidates"
      assert_includes @response.body, "New Error Fingerprints"
      assert_includes @response.body, "Since Current Deploy/Version"

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
      assert_includes @response.body, related_trace.name
      assert_includes @response.body, "/solid_errors/123"

      get "/solid_events/hot_path", params: {name: trace.name, source: trace.source, window: "7d"}
      assert_response :success
      assert_includes @response.body, "Hot Path Drilldown"
      assert_includes @response.body, "Hourly Buckets"
    end
  end
end
