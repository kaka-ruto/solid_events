# frozen_string_literal: true

require "test_helper"

module SolidEvents
  class BenchmarkTest < ActiveSupport::TestCase
    test "run returns benchmark payload shape" do
      SolidEvents::Trace.create!(
        name: "checkout.create",
        trace_type: "request",
        source: "CheckoutController#create",
        status: "ok",
        started_at: Time.current
      )
      SolidEvents::Summary.create!(
        trace: SolidEvents::Trace.last,
        name: "checkout.create",
        trace_type: "request",
        source: "CheckoutController#create",
        status: "ok",
        started_at: Time.current
      )
      SolidEvents::Incident.create!(
        kind: "error_spike",
        severity: "critical",
        status: "active",
        source: "CheckoutController#create",
        name: "checkout.create",
        payload: {},
        detected_at: Time.current,
        last_seen_at: Time.current
      )

      result = SolidEvents::Benchmark.run(sample_size: 10)
      assert_equal 10, result[:sample_size]
      assert result[:elapsed_ms].is_a?(Numeric)
      assert result[:generated_at].present?
      assert_equal 1, result[:traces_count]
      assert_equal 1, result[:summaries_count]
      assert_equal 1, result[:incidents_count]
    end
  end
end
