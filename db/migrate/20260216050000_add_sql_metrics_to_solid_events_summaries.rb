# frozen_string_literal: true

class AddSqlMetricsToSolidEventsSummaries < ActiveRecord::Migration[7.1]
  def change
    add_column :solid_events_summaries, :sql_count, :integer, null: false, default: 0 unless column_exists?(:solid_events_summaries, :sql_count)
    add_column :solid_events_summaries, :sql_duration_ms, :float, null: false, default: 0.0 unless column_exists?(:solid_events_summaries, :sql_duration_ms)
  end
end
