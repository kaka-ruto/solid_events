# frozen_string_literal: true

require "test_helper"

module SolidEvents
  class PruneJobTest < ActiveSupport::TestCase
    test "prunes success traces earlier than error traces and prunes incidents separately" do
      previous_retention = SolidEvents.configuration.retention_period
      previous_error_retention = SolidEvents.configuration.error_retention_period
      previous_incident_retention = SolidEvents.configuration.incident_retention_period

      SolidEvents.configuration.retention_period = 1.day
      SolidEvents.configuration.error_retention_period = 3.days
      SolidEvents.configuration.incident_retention_period = 5.days

      old_ok = SolidEvents::Trace.create!(
        name: "ok.trace",
        trace_type: "request",
        source: "OkController#index",
        status: "ok",
        started_at: 2.days.ago
      )
      recent_ok = SolidEvents::Trace.create!(
        name: "recent.ok",
        trace_type: "request",
        source: "OkController#show",
        status: "ok",
        started_at: 4.hours.ago
      )
      old_error = SolidEvents::Trace.create!(
        name: "old.error",
        trace_type: "request",
        source: "ErrorsController#index",
        status: "error",
        started_at: 4.days.ago
      )
      recent_error = SolidEvents::Trace.create!(
        name: "recent.error",
        trace_type: "request",
        source: "ErrorsController#show",
        status: "error",
        started_at: 2.days.ago
      )

      old_incident = SolidEvents::Incident.create!(
        kind: "error_spike",
        severity: "critical",
        status: "active",
        detected_at: 6.days.ago,
        last_seen_at: 6.days.ago
      )
      recent_incident = SolidEvents::Incident.create!(
        kind: "new_fingerprint",
        severity: "warning",
        status: "active",
        detected_at: 2.days.ago,
        last_seen_at: 2.days.ago
      )

      SolidEvents::PruneJob.perform_now

      refute SolidEvents::Trace.exists?(old_ok.id)
      assert SolidEvents::Trace.exists?(recent_ok.id)
      refute SolidEvents::Trace.exists?(old_error.id)
      assert SolidEvents::Trace.exists?(recent_error.id)
      refute SolidEvents::Incident.exists?(old_incident.id)
      assert SolidEvents::Incident.exists?(recent_incident.id)
    ensure
      SolidEvents.configuration.retention_period = previous_retention
      SolidEvents.configuration.error_retention_period = previous_error_retention
      SolidEvents.configuration.incident_retention_period = previous_incident_retention
    end
  end
end
