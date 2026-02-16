# frozen_string_literal: true

SolidEvents.configure do |config|
  # config.connects_to = { database: { writing: :solid_events } }
  config.ignore_paths = ["/up", "/health", "/assets", "/solid_events", "/solid_errors"]
  config.ignore_models = ["Ahoy::Event", "AuditLog"]
  # Namespace defaults are ignored across model links, SQL noise, and job traces.
  # Override with:
  # - config.ignore_namespaces << "my_engine"
  # - config.allow_sql_tables << "noticed_notifications"
  # - config.allow_sql_fragments << "active_storage_"
  # - config.allow_job_prefixes << "job.active_storage"
  config.retention_period = 30.days
end
