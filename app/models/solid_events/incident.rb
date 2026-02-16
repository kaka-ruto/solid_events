# frozen_string_literal: true

module SolidEvents
  class Incident < Record
    self.table_name = "solid_events_incidents"

    STATUSES = %w[active acknowledged resolved].freeze

    validates :kind, :severity, :detected_at, :last_seen_at, :status, presence: true
    validates :status, inclusion: {in: STATUSES}

    scope :recent, -> { order(detected_at: :desc) }
    scope :active_first, -> { order(Arel.sql("CASE status WHEN 'active' THEN 0 WHEN 'acknowledged' THEN 1 ELSE 2 END"), detected_at: :desc) }

    def acknowledge!
      update!(status: "acknowledged", acknowledged_at: Time.current)
    end

    def resolve!
      update!(status: "resolved", resolved_at: Time.current)
    end

    def reopen!
      update!(status: "active", resolved_at: nil)
    end
  end
end
