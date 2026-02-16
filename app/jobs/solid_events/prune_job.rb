# frozen_string_literal: true

module SolidEvents
  class PruneJob < ActiveJob::Base
    queue_as :default

    def perform
      success_cutoff = SolidEvents.retention_period.ago
      error_cutoff = SolidEvents.error_retention_period.ago
      incident_cutoff = SolidEvents.incident_retention_period.ago

      SolidEvents::Trace.where(status: "ok").where("started_at < ?", success_cutoff).delete_all
      SolidEvents::Trace.where(status: "error").where("started_at < ?", error_cutoff).delete_all
      prune_incidents_older_than(incident_cutoff)
    end

    private

    def prune_incidents_older_than(cutoff)
      return unless defined?(SolidEvents::Incident)
      return unless SolidEvents::Incident.connection.data_source_exists?(SolidEvents::Incident.table_name)

      SolidEvents::Incident.where("detected_at < ?", cutoff).delete_all
    end
  end
end
