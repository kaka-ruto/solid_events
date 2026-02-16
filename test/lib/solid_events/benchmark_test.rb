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

    test "evaluate returns pass warn and fail states" do
      pass = SolidEvents::Benchmark.evaluate(result: {elapsed_ms: 90}, warn_ms: 120, fail_ms: 200)
      warn = SolidEvents::Benchmark.evaluate(result: {elapsed_ms: 150}, warn_ms: 120, fail_ms: 200)
      fail_result = SolidEvents::Benchmark.evaluate(result: {elapsed_ms: 250}, warn_ms: 120, fail_ms: 200)

      assert_equal "pass", pass[:status]
      assert_equal "warn", warn[:status]
      assert_equal "fail", fail_result[:status]
    end
  end
end
