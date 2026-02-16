# frozen_string_literal: true

module SolidEvents
  class Incident < Record
    self.table_name = "solid_events_incidents"

    validates :kind, :severity, :detected_at, presence: true

    scope :recent, -> { order(detected_at: :desc) }
  end
end
