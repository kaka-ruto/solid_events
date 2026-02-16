# frozen_string_literal: true

require "test_helper"
require "digest"

unless defined?(::SolidErrors)
  module ::SolidErrors
    class Sanitizer
      def self.sanitize(value)
        value.to_s.gsub(/#<Class:0x[0-9a-f]+>/, "#<Class>")
      end
    end

    class Error
      class << self
        attr_accessor :by_fingerprint
      end
    end
  end
end

module SolidEvents
  module ActiveStorage
    class AnalyzeJob
      def self.name = "ActiveStorage::AnalyzeJob"

      def job_id = "job-1"

      def queue_name = "active_storage_analysis"
    end
  end

  class SubscribersTest < ActiveSupport::TestCase
    test "sql subscriber appends event to active trace" do
      SolidEvents::Tracer.start_trace!(name: "test", trace_type: "request", source: "x")
      subscriber = SolidEvents::Subscribers::SqlSubscriber.new
      subscriber.call("sql.active_record", Time.current, Time.current + 0.002, "1", {name: "SQL", sql: "select 1", cached: false})
      SolidEvents::Tracer.finish_trace!

      trace = SolidEvents::Trace.last
      assert_equal 1, trace.events.count
      assert_equal "sql", trace.events.first.event_type
    end

    test "sql subscriber ignores configured noise tables" do
      SolidEvents::Tracer.start_trace!(name: "test", trace_type: "request", source: "x")
      subscriber = SolidEvents::Subscribers::SqlSubscriber.new
      subscriber.call(
        "sql.active_record",
        Time.current,
        Time.current + 0.002,
        "1",
        {name: "SQL", sql: "SELECT * FROM solid_queue_ready_executions", cached: false}
      )
      SolidEvents::Tracer.finish_trace!

      trace = SolidEvents::Trace.last
      assert_equal 0, trace.events.count
    end

    test "job subscriber ignores active storage jobs" do
      subscriber = SolidEvents::Subscribers::JobSubscriber.new
      payload = {job: ActiveStorage::AnalyzeJob.new}

      subscriber.call("perform.active_job", Time.current, Time.current + 0.002, "1", payload)

      assert_equal 0, SolidEvents::Trace.count
      assert_equal 0, SolidEvents::Event.count
    end

    test "error subscriber links current trace using fingerprint" do
      trace = SolidEvents::Tracer.start_trace!(name: "test", trace_type: "request", source: "x")
      subscriber = SolidEvents::Subscribers::ErrorSubscriber.new

      error = RuntimeError.new("undefined local variable or method 's' for an instance of #<Class:0x1234>")
      fingerprint = Digest::SHA256.hexdigest(
        [error.class.name, SolidErrors::Sanitizer.sanitize(error.message), :error, "application"].join
      )

      fake_error = Struct.new(:id).new(99)
      SolidErrors::Error.by_fingerprint = {fingerprint => fake_error}
      SolidErrors::Error.singleton_class.define_method(:find_by) do |conditions|
        by_fingerprint[conditions[:fingerprint]]
      end

      subscriber.report(error, handled: false, severity: :error, context: {}, source: "application")
      SolidEvents::Tracer.finish_trace!(status: "error")

      assert_equal 1, trace.reload.error_links.count
      assert_equal 99, trace.error_links.first.solid_error_id
      assert_equal fingerprint, trace.context["error_fingerprint"]
    ensure
      SolidErrors::Error.by_fingerprint = {}
    end

    test "error subscriber links bound trace when current trace is cleared" do
      trace = SolidEvents::Tracer.start_trace!(name: "test", trace_type: "request", source: "x")
      subscriber = SolidEvents::Subscribers::ErrorSubscriber.new

      error = RuntimeError.new("bound trace error")
      fingerprint = Digest::SHA256.hexdigest(
        [error.class.name, SolidErrors::Sanitizer.sanitize(error.message), :error, "application.action_dispatch"].join
      )

      fake_error = Struct.new(:id).new(100)
      SolidErrors::Error.by_fingerprint = {fingerprint => fake_error}
      SolidErrors::Error.singleton_class.define_method(:find_by) do |conditions|
        by_fingerprint[conditions[:fingerprint]]
      end

      SolidEvents::Tracer.bind_exception_to_trace!(error, trace: trace)
      SolidEvents::Current.trace = nil

      subscriber.report(error, handled: false, severity: :error, context: {}, source: "application.action_dispatch")

      assert_equal 1, trace.reload.error_links.count
      assert_equal 100, trace.error_links.first.solid_error_id
    ensure
      SolidErrors::Error.by_fingerprint = {}
    end
  end
end
