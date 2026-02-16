# frozen_string_literal: true

module SolidEvents
  module Subscribers
    class SqlSubscriber
      IGNORED = %w[SCHEMA TRANSACTION].freeze

      def call(_name, started, finished, _unique_id, payload)
        return if IGNORED.include?(payload[:name].to_s)
        sql = payload[:sql].to_s
        downcased_sql = sql.downcase
        return if ignored_sql_tables_in_statement(downcased_sql).any?
        return if SolidEvents.ignore_sql_fragments.any? { |fragment| downcased_sql.include?(fragment.to_s.downcase) }

        SolidEvents::Tracer.record_event!(
          event_type: "sql",
          name: payload[:name].to_s,
          payload: payload.slice(:sql, :cached),
          duration_ms: ((finished - started) * 1000.0).round(2)
        )
      end

      private

      def ignored_sql_tables_in_statement(downcased_sql)
        statement_tables = extract_statement_tables(downcased_sql)
        return [] if statement_tables.empty?

        statement_tables & known_noisy_tables
      end

      def known_noisy_tables
        @known_noisy_tables ||= begin
          sources = ActiveRecord::Base.connection.data_sources.map(&:downcase)
          SolidEvents.ignore_sql_tables(sources)
        rescue StandardError
          []
        end
      end

      def extract_statement_tables(sql)
        sql.scan(/\b(?:from|join|update|into)\s+"?([a-z0-9_]+)"?/).flatten.uniq
      end
    end
  end
end
