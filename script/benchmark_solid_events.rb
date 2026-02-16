#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require_relative "../test/dummy/config/environment"
require "solid_events"

sample_size = (ARGV[0] || 200).to_i
result = SolidEvents::Benchmark.run(sample_size: sample_size)
puts JSON.pretty_generate(result)
