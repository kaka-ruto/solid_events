# frozen_string_literal: true

require "test_helper"
require "digest"

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
    class DummyRecord < ApplicationRecord
      self.table_name = "solid_events_traces"
    end

    module SolidQueue
      class DummyRecord
        attr_reader :id

        def initialize(id)
          @id = id
        end
      end
    end

    test "creates trace events and links" do
      trace = SolidEvents::Tracer.start_trace!(name: "order.created", trace_type: "request", source: "OrdersController#create", context: {user_id: 1})

      SolidEvents::Tracer.record_event!(event_type: "sql", name: "SELECT", payload: {sql: "select 1"}, duration_ms: 1.3)
      SolidEvents::Tracer.link_error!(123)
      SolidEvents::Tracer.finish_trace!(status: "ok")

      trace.reload
      assert_equal 1, trace.events.count
      assert_equal 1, trace.error_links.count
      assert_equal "ok", trace.status
      assert_not_nil trace.finished_at
      assert_not_nil trace.summary
      assert_equal 1, trace.summary.event_count
      assert_equal 1, trace.summary.error_count
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
  end
end
