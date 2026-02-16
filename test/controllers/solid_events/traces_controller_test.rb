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
        started_at: trace.started_at,
        event_count: 1,
        record_link_count: 0,
        error_count: 1
      )

      get "/solid_events"
      assert_response :success
      assert_includes @response.body, "Context Graph"

      get "/solid_events", params: {entity_type: "Order", entity_id: "987"}
      assert_response :success

      get "/solid_events/#{trace.id}"
      assert_response :success
      assert_includes @response.body, "Trace ##{trace.id}"
      assert_includes @response.body, "Canonical Event"
      assert_includes @response.body, "Summary Dimensions"
      assert_includes @response.body, "Correlation Pivots"
      assert_includes @response.body, "/solid_errors/123"
    end
  end
end
