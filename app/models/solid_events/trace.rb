# frozen_string_literal: true

module SolidEvents
  class Trace < Record
    self.table_name = "solid_events_traces"

    has_many :events, class_name: "SolidEvents::Event", dependent: :delete_all
    has_many :record_links, class_name: "SolidEvents::RecordLink", dependent: :delete_all
    has_many :error_links, class_name: "SolidEvents::ErrorLink", dependent: :delete_all
    has_one :summary, class_name: "SolidEvents::Summary", dependent: :delete

    validates :name, :trace_type, :source, :started_at, presence: true

    scope :recent, -> { order(started_at: :desc) }

    def canonical_event
      if summary
        return {
          trace_id: id,
          name: summary.name,
          trace_type: summary.trace_type,
          source: summary.source,
          status: summary.status,
          started_at: summary.started_at,
          finished_at: summary.finished_at,
          duration_ms: summary.duration_ms,
          event_count: summary.event_count,
          record_link_count: summary.record_link_count,
          error_count: summary.error_count,
          user_id: summary.user_id,
          account_id: summary.account_id,
          error_fingerprint: summary.error_fingerprint,
          payload: summary.payload.to_h
        }
      end

      {
        trace_id: id,
        name: name,
        trace_type: trace_type,
        source: source,
        status: status,
        started_at: started_at,
        finished_at: finished_at,
        duration_ms: duration_ms,
        event_counts: events.group(:event_type).count,
        record_link_count: record_links.count,
        error_link_ids: error_links.pluck(:solid_error_id),
        context: context.to_h
      }
    end

    private

    def duration_ms
      return nil unless started_at && finished_at

      ((finished_at - started_at) * 1000.0).round(2)
    end
  end
end
