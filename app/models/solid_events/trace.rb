# frozen_string_literal: true

module SolidEvents
  class Trace < Record
    self.table_name = "solid_events_traces"

    has_many :events, class_name: "SolidEvents::Event", dependent: :delete_all
    has_many :record_links, class_name: "SolidEvents::RecordLink", dependent: :delete_all
    has_many :error_links, class_name: "SolidEvents::ErrorLink", dependent: :delete_all

    validates :name, :trace_type, :source, :started_at, presence: true

    scope :recent, -> { order(started_at: :desc) }

    def canonical_event
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
