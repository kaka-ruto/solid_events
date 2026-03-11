# frozen_string_literal: true

class AddSchemaVersionToSolidEventsSummaries < ActiveRecord::Migration[7.1]
  def change
    add_column :solid_events_summaries, :schema_version, :string, null: false, default: "1" unless column_exists?(:solid_events_summaries, :schema_version)
  end
end
