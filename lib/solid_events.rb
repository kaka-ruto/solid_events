# frozen_string_literal: true

require_relative "solid_events/version"
require_relative "solid_events/configuration"
require_relative "solid_events/current"
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
  end
end
