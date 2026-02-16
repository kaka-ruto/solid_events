# frozen_string_literal: true

require "test_helper"
require "digest"
require "json"

class ::LinkedOrderRecord
  attr_reader :id

  def initialize(id)
    @id = id
  end
end

class ::TestLogger
  attr_reader :lines

  def initialize
    @lines = []
  end

  def info(message)
    @lines << message
  end
end

unless defined?(::SolidErrors)
  module ::SolidErrors
  end
end

unless defined?(::SolidErrors::Sanitizer)
  class ::SolidErrors::Sanitizer
    def self.sanitize(value)
      value.to_s
    end
  end
end

unless defined?(::SolidErrors::Error)
  class ::SolidErrors::Error
  end
end

class ::SolidErrors::Error
  class << self
    attr_accessor :records
  end

  self.records ||= []

  def self.where(conditions)
    matches = records.select do |record|
      conditions.all? { |key, value| record.public_send(key) == value }
    end
    Relation.new(matches)
  end

  class Relation
    def initialize(records)
      @records = records
    end

    def order(updated_at: :desc)
      sorted = @records.sort_by(&:updated_at)
      sorted.reverse! if updated_at == :desc
      self.class.new(sorted)
    end

    def first
      @records.first
    end
  end
end

module SolidEvents
  class TracerTest < ActiveSupport::TestCase
    module SolidQueue
      class DummyRecord
        attr_reader :id

        def initialize(id)
          @id = id
        end
      end
    end

    test "creates trace events and links" do
      trace = SolidEvents::Tracer.start_trace!(
        name: "order.created",
        trace_type: "request",
        source: "OrdersController#create",
        context: {
          user_id: 1,
          path: "/orders",
          method: "POST",
          request_id: "req-1",
          service_name: "anywaye",
          environment_name: "production",
          service_version: "2026.02.16",
          deployment_id: "deploy-1",
          region: "us-east-1"
        }
      )

      linked_record = ::LinkedOrderRecord.new(42)

      SolidEvents::Tracer.record_event!(event_type: "sql", name: "SELECT", payload: {sql: "select 1"}, duration_ms: 1.3)
      SolidEvents::Tracer.link_record!(linked_record)
      SolidEvents::Tracer.link_error!(123)
      SolidEvents::Tracer.finish_trace!(status: "ok", context: {status: 201})

      trace.reload
      assert_equal 1, trace.events.count
      assert_equal 1, trace.record_links.count
      assert_equal 1, trace.error_links.count
      assert_equal "ok", trace.status
      assert_not_nil trace.finished_at
      assert_not_nil trace.summary
      assert_equal 1, trace.summary.event_count
      assert_equal 1, trace.summary.record_link_count
      assert_equal 1, trace.summary.error_count
      assert_equal "success", trace.summary.outcome
      assert_equal linked_record.class.name, trace.summary.entity_type
      assert_equal linked_record.id, trace.summary.entity_id
      assert_equal 201, trace.summary.http_status
      assert_equal "POST", trace.summary.request_method
      assert_equal "req-1", trace.summary.request_id
      assert_equal "/orders", trace.summary.path
      assert_equal 1, trace.summary.sql_count
      assert_equal 1.3, trace.summary.sql_duration_ms
      assert_equal "anywaye", trace.summary.service_name
      assert_equal "production", trace.summary.environment_name
      assert_equal "2026.02.16", trace.summary.service_version
      assert_equal "deploy-1", trace.summary.deployment_id
      assert_equal "us-east-1", trace.summary.region
    end

    test "does not link ignored model prefixes" do
      trace = SolidEvents::Tracer.start_trace!(name: "test", trace_type: "request", source: "x")
      noisy = SolidQueue::DummyRecord.new(123)

      SolidEvents::Tracer.link_record!(noisy)
      SolidEvents::Tracer.finish_trace!(status: "ok")

      assert_equal 0, trace.reload.record_links.count
    end

    test "reconciles error link from trace exception context" do
      trace = SolidEvents::Tracer.start_trace!(name: "failing.request", trace_type: "request", source: "x")
      SolidEvents::Tracer.finish_trace!(
        status: "error",
        context: {"exception_class" => "NoMethodError", "exception_message" => "undefined method foo"}
      )

      solid_error = Struct.new(:id, :exception_class, :message, :updated_at)
      SolidErrors::Error.records = [solid_error.new(42, "NoMethodError", "undefined method foo", Time.current)]

      SolidEvents::Tracer.reconcile_error_link_for_trace!(trace.reload, attempts: 1)

      assert_equal 1, trace.reload.error_links.count
      assert_equal 42, trace.error_links.first.solid_error_id
    ensure
      SolidErrors::Error.records = []
    end

    test "reconciles with wrapped exception using cause chain" do
      trace = SolidEvents::Tracer.start_trace!(name: "wrapped.failure", trace_type: "request", source: "x")
      SolidEvents::Tracer.finish_trace!(status: "error")

      inner_exception = nil
      wrapped_exception = begin
        begin
          raise NameError, "undefined local variable or method missing_ref"
        rescue StandardError => e
          inner_exception = e
          raise RuntimeError, "template wrapper"
        end
      rescue StandardError => e
        e
      end

      solid_error = Struct.new(:id, :exception_class, :message, :updated_at)
      SolidErrors::Error.records = [
        solid_error.new(77, "NameError", SolidErrors::Sanitizer.sanitize(inner_exception.message), Time.current)
      ]

      SolidEvents::Tracer.reconcile_error_link_for_trace!(trace.reload, attempts: 1, exception: wrapped_exception)

      assert_equal 1, trace.reload.error_links.count
      assert_equal 77, trace.error_links.first.solid_error_id
    ensure
      SolidErrors::Error.records = []
    end

    test "error fingerprint uses root cause for wrapped exceptions" do
      wrapped_exception = begin
        begin
          raise NameError, "undefined local variable or method missing_ref"
        rescue StandardError
          raise RuntimeError, "template wrapper"
        end
      rescue StandardError => e
        e
      end

      fingerprint = SolidEvents::Tracer.error_fingerprint_for(
        wrapped_exception,
        severity: :error,
        source: "application.action_dispatch"
      )
      expected = Digest::SHA256.hexdigest(
        ["NameError", SolidErrors::Sanitizer.sanitize("undefined local variable or method missing_ref"), :error, "application.action_dispatch"].join
      )

      assert_equal expected, fingerprint
    end

    test "tail sampling drops fast success traces when sample rate is zero" do
      previous_sample_rate = SolidEvents.configuration.sample_rate
      previous_slow_ms = SolidEvents.configuration.tail_sample_slow_ms
      SolidEvents.configuration.sample_rate = 0.0
      SolidEvents.configuration.tail_sample_slow_ms = 999_999

      SolidEvents::Tracer.start_trace!(name: "sampled.out", trace_type: "request", source: "x")
      SolidEvents::Tracer.record_event!(event_type: "sql", name: "SELECT", payload: {sql: "select 1"}, duration_ms: 1.0)
      result = SolidEvents::Tracer.finish_trace!(status: "ok", context: {status: 200})

      assert_nil result
      assert_equal 0, SolidEvents::Trace.count
      assert_equal 0, SolidEvents::Event.count
    ensure
      SolidEvents.configuration.sample_rate = previous_sample_rate
      SolidEvents.configuration.tail_sample_slow_ms = previous_slow_ms
    end

    test "tail sampling always keeps error traces even when sample rate is zero" do
      previous_sample_rate = SolidEvents.configuration.sample_rate
      SolidEvents.configuration.sample_rate = 0.0

      trace = SolidEvents::Tracer.start_trace!(name: "failed.trace", trace_type: "request", source: "x")
      SolidEvents::Tracer.finish_trace!(status: "error", context: {status: 500})

      assert_equal trace.id, SolidEvents::Trace.last.id
    ensure
      SolidEvents.configuration.sample_rate = previous_sample_rate
    end

    test "emits one canonical json line when trace is persisted" do
      previous_logger = Rails.logger
      previous_emit = SolidEvents.configuration.emit_canonical_log_line
      logger = ::TestLogger.new
      Rails.logger = logger
      SolidEvents.configuration.emit_canonical_log_line = true

      SolidEvents::Tracer.start_trace!(name: "logged.trace", trace_type: "request", source: "x")
      SolidEvents::Tracer.finish_trace!(status: "ok", context: {status: 200})

      assert_equal 1, logger.lines.length
      payload = JSON.parse(logger.lines.first)
      assert_equal "logged.trace", payload["name"]
      assert_equal "ok", payload["status"]
    ensure
      Rails.logger = previous_logger
      SolidEvents.configuration.emit_canonical_log_line = previous_emit
    end

    test "annotate merges additional business context into active trace" do
      trace = SolidEvents::Tracer.start_trace!(
        name: "checkout.started",
        trace_type: "request",
        source: "CheckoutsController#create",
        context: {request_id: "req-2"}
      )

      SolidEvents.annotate!(plan: "pro", cart_value_cents: 8999)
      SolidEvents::Tracer.finish_trace!(status: "ok")

      context = trace.reload.context.to_h
      assert_equal "pro", context["plan"]
      assert_equal 8999, context["cart_value_cents"]
    end
  end
end
