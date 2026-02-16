# frozen_string_literal: true

module SolidEvents
  class Incident < Record
    self.table_name = "solid_events_incidents"

    STATUSES = %w[active acknowledged resolved].freeze

    validates :kind, :severity, :detected_at, :last_seen_at, :status, presence: true
    validates :status, inclusion: {in: STATUSES}

    has_many :incident_events, class_name: "SolidEvents::IncidentEvent", dependent: :delete_all

    scope :recent, -> { order(detected_at: :desc) }
    scope :active_first, -> { order(Arel.sql("CASE status WHEN 'active' THEN 0 WHEN 'acknowledged' THEN 1 ELSE 2 END"), detected_at: :desc) }
    scope :unmuted, -> { where("muted_until IS NULL OR muted_until < ?", Time.current) }

    def acknowledge!
      update!(status: "acknowledged", acknowledged_at: Time.current)
      record_event!(action: "acknowledged")
    end

    def resolve!
      update!(status: "resolved", resolved_at: Time.current)
      record_event!(action: "resolved")
    end

    def reopen!
      update!(status: "active", resolved_at: nil, resolved_by: nil, resolution_note: nil)
      record_event!(action: "reopened")
    end

    def mute_for!(duration)
      update!(muted_until: duration.from_now)
      record_event!(action: "muted", payload: {muted_until: muted_until})
    end

    def assign!(owner:, team: nil, assigned_by: nil, assignment_note: nil)
      update!(
        owner: owner,
        team: team,
        assigned_by: assigned_by,
        assignment_note: assignment_note,
        assigned_at: Time.current
      )
      record_event!(action: "assigned", actor: assigned_by, payload: {owner: owner, team: team, assignment_note: assignment_note})
    end

    def resolve_with!(resolved_by:, resolution_note: nil)
      update!(
        status: "resolved",
        resolved_at: Time.current,
        resolved_by: resolved_by,
        resolution_note: resolution_note
      )
      record_event!(action: "resolved", actor: resolved_by, payload: {resolution_note: resolution_note})
    end

    def record_event!(action:, actor: nil, payload: {})
      incident_events.create!(
        action: action,
        actor: actor,
        payload: payload,
        occurred_at: Time.current
      )
    end
  end
end
