# frozen_string_literal: true

module SolidEvents
  class Trace < Record
    self.table_name = "solid_events_traces"

    has_many :events, class_name: "SolidEvents::Event", dependent: :delete_all
    has_many :record_links, class_name: "SolidEvents::RecordLink", dependent: :delete_all
    has_many :error_links, class_name: "SolidEvents::ErrorLink", dependent: :delete_all

    validates :name, :trace_type, :source, :started_at, presence: true

    scope :recent, -> { order(started_at: :desc) }
  end
end
