# frozen_string_literal: true

module SolidEvents
  class Configuration
    DEFAULT_IGNORE_NAMESPACES = %w[
      solid_events
      solid_errors
      solid_queue
      solid_cache
      solid_cable
      active_storage
      action_text
      noticed
    ].freeze
    DEFAULT_IGNORE_MODEL_PREFIXES = %w[Noticed::].freeze
    DEFAULT_IGNORE_SQL_FRAGMENTS = %w[schema_migrations ar_internal_metadata].freeze

    CORE_IGNORE_MODELS = %w[
      SolidEvents::Trace
      SolidEvents::Event
      SolidEvents::RecordLink
      SolidEvents::ErrorLink
    ].freeze

    attr_accessor :connects_to, :ignore_paths, :retention_period, :ignore_namespaces,
                  :ignore_sql_fragments, :ignore_model_prefixes, :ignore_job_prefixes,
                  :ignore_controller_prefixes,
                  :ignore_sql_tables, :allow_sql_fragments, :allow_model_prefixes, :allow_job_prefixes,
                  :allow_sql_tables, :allow_controller_prefixes
    attr_reader :ignore_models

    def initialize
      @connects_to = nil
      @ignore_models = CORE_IGNORE_MODELS.dup
      @ignore_paths = %w[/up /health /assets /rails/active_storage]
      @ignore_namespaces = DEFAULT_IGNORE_NAMESPACES.dup
      @ignore_model_prefixes = []
      @ignore_sql_fragments = []
      @ignore_sql_tables = []
      @ignore_job_prefixes = []
      @ignore_controller_prefixes = []
      @allow_model_prefixes = []
      @allow_sql_fragments = []
      @allow_sql_tables = []
      @allow_job_prefixes = []
      @allow_controller_prefixes = []
      @retention_period = 30.days
    end

    def ignore_models=(models)
      configured_models = Array(models).map(&:to_s)
      @ignore_models = (CORE_IGNORE_MODELS + configured_models).uniq
    end

    def effective_ignore_model_prefixes
      defaults = namespace_model_prefixes + DEFAULT_IGNORE_MODEL_PREFIXES
      ((defaults + Array(@ignore_model_prefixes).map(&:to_s)) - Array(@allow_model_prefixes).map(&:to_s)).uniq
    end

    def effective_ignore_sql_fragments
      defaults = namespace_sql_fragments + DEFAULT_IGNORE_SQL_FRAGMENTS
      ((defaults + Array(@ignore_sql_fragments).map(&:to_s)) - Array(@allow_sql_fragments).map(&:to_s)).uniq
    end

    def effective_ignore_sql_tables(present_tables = [])
      namespace_prefixes = namespace_sql_fragments
      default_from_present = Array(present_tables).map(&:to_s).select do |table|
        namespace_prefixes.any? { |prefix| table.start_with?(prefix) }
      end
      explicit = Array(@ignore_sql_tables).map(&:to_s)
      allows = Array(@allow_sql_tables).map(&:to_s)

      ((default_from_present + explicit) - allows).uniq
    end

    def effective_ignore_job_prefixes
      defaults = namespace_job_prefixes
      ((defaults + Array(@ignore_job_prefixes).map(&:to_s)) - Array(@allow_job_prefixes).map(&:to_s)).uniq
    end

    def effective_ignore_controller_prefixes
      defaults = namespace_model_prefixes
      ((defaults + Array(@ignore_controller_prefixes).map(&:to_s)) - Array(@allow_controller_prefixes).map(&:to_s)).uniq
    end

    private

    def namespace_model_prefixes
      Array(@ignore_namespaces).map { |namespace| "#{namespace.to_s.camelize}::" }
    end

    def namespace_sql_fragments
      Array(@ignore_namespaces).map { |namespace| "#{namespace}_" }
    end

    def namespace_job_prefixes
      Array(@ignore_namespaces).map { |namespace| "job.#{namespace}" }
    end
  end
end
