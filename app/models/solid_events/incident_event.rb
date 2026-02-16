# frozen_string_literal: true

module SolidEvents
  class IncidentEvent < Record
    self.table_name = "solid_events_incident_events"

    belongs_to :incident, class_name: "SolidEvents::Incident"

    validates :action, :occurred_at, presence: true

    scope :recent, -> { order(occurred_at: :desc) }
  end
end
