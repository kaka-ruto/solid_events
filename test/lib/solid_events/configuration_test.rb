# frozen_string_literal: true

require "test_helper"

module SolidEvents
  class ConfigurationTest < ActiveSupport::TestCase
    test "ignore_models always keeps core solid events models" do
      configuration = SolidEvents::Configuration.new
      configuration.ignore_models = ["Ahoy::Event", "AuditLog"]

      assert_includes configuration.ignore_models, "Ahoy::Event"
      assert_includes configuration.ignore_models, "AuditLog"
      assert_includes configuration.ignore_models, "SolidEvents::Trace"
      assert_includes configuration.ignore_models, "SolidEvents::Event"
      assert_includes configuration.ignore_models, "SolidEvents::RecordLink"
      assert_includes configuration.ignore_models, "SolidEvents::ErrorLink"
    end

    test "namespace defaults include active storage filtering" do
      configuration = SolidEvents::Configuration.new

      assert_includes configuration.effective_ignore_job_prefixes, "job.active_storage"
      assert_includes configuration.effective_ignore_sql_fragments, "active_storage_"
      assert_includes configuration.effective_ignore_model_prefixes, "ActiveStorage::"
      assert_includes configuration.effective_ignore_controller_prefixes, "ActiveStorage::"
    end

    test "allow lists can re-enable default ignored namespaces" do
      configuration = SolidEvents::Configuration.new
      configuration.allow_job_prefixes = ["job.active_storage"]
      configuration.allow_sql_fragments = ["active_storage_"]
      configuration.allow_model_prefixes = ["ActiveStorage::"]
      configuration.allow_controller_prefixes = ["ActiveStorage::"]

      refute_includes configuration.effective_ignore_job_prefixes, "job.active_storage"
      refute_includes configuration.effective_ignore_sql_fragments, "active_storage_"
      refute_includes configuration.effective_ignore_model_prefixes, "ActiveStorage::"
      refute_includes configuration.effective_ignore_controller_prefixes, "ActiveStorage::"
    end

    test "effective sql tables derive from present tables and can be overridden" do
      configuration = SolidEvents::Configuration.new
      present_tables = %w[users active_storage_blobs noticed_notifications]

      ignored = configuration.effective_ignore_sql_tables(present_tables)
      assert_includes ignored, "active_storage_blobs"
      assert_includes ignored, "noticed_notifications"
      refute_includes ignored, "users"

      configuration.allow_sql_tables = ["noticed_notifications"]
      ignored_after_allow = configuration.effective_ignore_sql_tables(present_tables)
      refute_includes ignored_after_allow, "noticed_notifications"
    end

    test "tail sampling defaults are configured" do
      configuration = SolidEvents::Configuration.new

      assert_equal 1.0, configuration.sample_rate
      assert_equal 2000.0, configuration.tail_sample_slow_ms
      assert_equal [], configuration.always_sample_context_keys
      assert_equal true, configuration.emit_canonical_log_line
      assert_predicate configuration.service_name, :present?
      assert_predicate configuration.environment_name, :present?
      assert_includes configuration.sensitive_keys, "password"
      assert_equal "[REDACTED]", configuration.redaction_placeholder
      assert_equal false, configuration.wide_event_primary
      assert_equal true, configuration.persist_sub_events
      assert_equal 20.0, configuration.incident_error_spike_threshold_pct
      assert_equal 1.5, configuration.incident_p95_regression_factor
      assert_equal 20, configuration.incident_min_samples
    end
  end
end
