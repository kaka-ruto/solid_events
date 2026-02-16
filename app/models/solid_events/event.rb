# frozen_string_literal: true

module SolidEvents
  class Event < Record
    self.table_name = "solid_events_events"

    belongs_to :trace, class_name: "SolidEvents::Trace"

    validates :event_type, :name, :occurred_at, presence: true
  end
end
