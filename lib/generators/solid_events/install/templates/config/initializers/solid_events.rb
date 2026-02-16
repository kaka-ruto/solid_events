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
  # Tail sampling keeps errors and slow traces, and samples the rest.
  # config.sample_rate = 0.2
  # config.tail_sample_slow_ms = 1000
  # config.always_sample_context_keys = ["release", "request_id"]
  # config.always_sample_when = ->(trace:, context:, duration_ms:) { context["tenant_id"].present? }
  # Emit one canonical JSON log line per sampled trace.
  # config.emit_canonical_log_line = true
  # Built-in PII redaction for canonical traces/events.
  # config.sensitive_keys += ["customer_email", "phone_number"]
  # config.redaction_placeholder = "[FILTERED]"
  config.retention_period = 30.days
end
