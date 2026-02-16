# frozen_string_literal: true

require "test_helper"

module SolidEvents
  class EvaluateIncidentsJobTest < ActiveSupport::TestCase
    test "runs incident evaluator without raising" do
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
        error_fingerprint: "fp-job",
        event_count: 1,
        record_link_count: 0,
        error_count: 1
      )

      assert_nothing_raised do
        SolidEvents::EvaluateIncidentsJob.perform_now
      end
    end
  end
end
