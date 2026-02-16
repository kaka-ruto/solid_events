#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require_relative "../test/dummy/config/environment"
require "solid_events"

sample_size = (ARGV[0] || 200).to_i
warn_ms = (ARGV[1] || 150).to_f
fail_ms = (ARGV[2] || 250).to_f

result = SolidEvents::Benchmark.run(sample_size: sample_size)
evaluation = SolidEvents::Benchmark.evaluate(result: result, warn_ms: warn_ms, fail_ms: fail_ms)
puts JSON.pretty_generate(result.merge(evaluation: evaluation))

exit 1 if evaluation[:status] == "fail"
