# frozen_string_literal: true

module SolidEvents
  module TracesHelper
    include ActionView::Helpers::DateHelper
    include ActionView::Helpers::NumberHelper

    def trace_status_badge(status)
      case status.to_s
      when "ok" then "ok"
      when "error" then "error"
      else "muted"
      end
    end

    def formatted_trace_duration(trace)
      return "n/a" unless trace.finished_at && trace.started_at

      "#{((trace.finished_at - trace.started_at) * 1000.0).round(2)} ms"
    end

    def relative_time(time)
      return "n/a" unless time

      "#{time_ago_in_words(time)} ago"
    end

    def absolute_time(time)
      return "n/a" unless time

      time.strftime("%Y-%m-%d %H:%M:%S %Z")
    end

    def event_payload_summary(event)
      payload = event.payload.to_h
      return "{}" if payload.empty?

      if event.event_type == "sql"
        sql = payload["sql"] || payload[:sql]
        return truncate(sql.to_s.squish, length: 160) if sql.present?
      end

      truncate(payload.to_json, length: 160)
    rescue StandardError
      "{}"
    end

    def trace_event_count(trace)
      trace.summary&.event_count || trace.events.size
    end

    def trace_record_link_count(trace)
      trace.summary&.record_link_count || trace.record_links.size
    end

    def trace_error_link_count(trace)
      trace.summary&.error_count || trace.error_links.size
    end
  end
end
