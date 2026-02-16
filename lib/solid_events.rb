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
  end
end
