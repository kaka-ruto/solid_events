# frozen_string_literal: true

require_relative "solid_events/version"
require_relative "solid_events/configuration"
require_relative "solid_events/current"
require_relative "solid_events/benchmark"
require_relative "solid_events/engine"

module SolidEvents
  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def connects_to
      configuration.connects_to
    end

    def ignore_models
      Array(configuration.ignore_models)
    end

    def ignore_paths
      Array(configuration.ignore_paths)
    end

    def ignore_model_prefixes
      Array(configuration.effective_ignore_model_prefixes)
    end

    def retention_period
      configuration.retention_period
    end

    def error_retention_period
      configuration.error_retention_period
    end

    def incident_retention_period
      configuration.incident_retention_period
    end

    def ignore_sql_fragments
      Array(configuration.effective_ignore_sql_fragments)
    end

    def ignore_sql_tables(present_tables = [])
      Array(configuration.effective_ignore_sql_tables(present_tables))
    end

    def ignore_job_prefixes
      Array(configuration.effective_ignore_job_prefixes)
    end

    def ignore_controller_prefixes
      Array(configuration.effective_ignore_controller_prefixes)
    end

    def sample_rate
      configuration.sample_rate.to_f
    end

    def tail_sample_slow_ms
      configuration.tail_sample_slow_ms.to_f
    end

    def always_sample_context_keys
      Array(configuration.always_sample_context_keys).map(&:to_s)
    end

    def always_sample_when
      configuration.always_sample_when
    end

    def emit_canonical_log_line?
      !!configuration.emit_canonical_log_line
    end

    def annotate!(context = {})
      SolidEvents::Tracer.annotate!(context)
    end

    def service_name
      configuration.service_name
    end

    def service_version
      configuration.service_version
    end

    def deployment_id
      configuration.deployment_id
    end

    def environment_name
      configuration.environment_name
    end

    def region
      configuration.region
    end

    def sensitive_keys
      Array(configuration.sensitive_keys).map(&:to_s)
    end

    def redaction_paths
      configuration.redaction_paths.to_h.transform_keys(&:to_s)
    end

    def redaction_placeholder
      configuration.redaction_placeholder.to_s
    end

    def max_context_payload_bytes
      configuration.max_context_payload_bytes.to_i
    end

    def max_event_payload_bytes
      configuration.max_event_payload_bytes.to_i
    end

    def payload_truncation_placeholder
      configuration.payload_truncation_placeholder.to_s
    end

    def wide_event_primary?
      !!configuration.wide_event_primary
    end

    def persist_sub_events?
      !!configuration.persist_sub_events
    end

    def incident_error_spike_threshold_pct
      configuration.incident_error_spike_threshold_pct.to_f
    end

    def incident_p95_regression_factor
      configuration.incident_p95_regression_factor.to_f
    end

    def incident_min_samples
      configuration.incident_min_samples.to_i
    end

    def incident_dedupe_window
      configuration.incident_dedupe_window
    end

    def incident_slo_target_error_rate_pct
      configuration.incident_slo_target_error_rate_pct.to_f
    end

    def incident_slo_burn_rate_threshold
      configuration.incident_slo_burn_rate_threshold.to_f
    end

    def incident_multi_signal_error_rate_pct
      configuration.incident_multi_signal_error_rate_pct.to_f
    end

    def incident_multi_signal_p95_factor
      configuration.incident_multi_signal_p95_factor.to_f
    end

    def incident_multi_signal_sql_duration_ms
      configuration.incident_multi_signal_sql_duration_ms.to_f
    end

    def incident_suppression_rules
      Array(configuration.incident_suppression_rules)
    end

    def incident_notifier
      configuration.incident_notifier
    end

    def api_token
      configuration.api_token
    end

    def evaluate_incidents_on_request?
      !!configuration.evaluate_incidents_on_request
    end

    def feature_slice_keys
      Array(configuration.feature_slice_keys).map(&:to_s)
    end

    def canonical_schema_version
      "1"
    end
  end
end
