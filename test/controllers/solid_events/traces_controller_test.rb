# frozen_string_literal: true

require "test_helper"

module SolidEvents
  class TracesControllerTest < ActionDispatch::IntegrationTest
    test "index and show" do
      trace = SolidEvents::Trace.create!(name: "order.created", trace_type: "request", source: "OrdersController#create", status: "ok", context: {}, started_at: Time.current)
      trace.events.create!(event_type: "controller", name: "OrdersController#create", payload: {}, occurred_at: Time.current)
      trace.error_links.create!(solid_error_id: 123)

      get "/solid_events"
      assert_response :success
      assert_includes @response.body, "Context Graph"

      get "/solid_events/#{trace.id}"
      assert_response :success
      assert_includes @response.body, "Trace ##{trace.id}"
      assert_includes @response.body, "Canonical Event"
      assert_includes @response.body, "/solid_errors/123"
    end
  end
end
