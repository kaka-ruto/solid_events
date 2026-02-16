# frozen_string_literal: true

class CreateSolidEventsSummaries < ActiveRecord::Migration[7.1]
  def change
    return if table_exists?(:solid_events_summaries)

    create_table :solid_events_summaries do |t|
      t.references :trace, null: false, index: {unique: true}, foreign_key: {to_table: :solid_events_traces}
      t.string :name, null: false
      t.string :trace_type, null: false
      t.string :source, null: false
      t.string :status, null: false, default: "ok"
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.float :duration_ms
      t.integer :event_count, null: false, default: 0
      t.integer :record_link_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.bigint :user_id
      t.bigint :account_id
      t.string :error_fingerprint
      t.json :payload, default: {}
      t.timestamps
    end

    add_index :solid_events_summaries, :status
    add_index :solid_events_summaries, :started_at
    add_index :solid_events_summaries, :duration_ms
    add_index :solid_events_summaries, :user_id
    add_index :solid_events_summaries, :account_id
    add_index :solid_events_summaries, :error_fingerprint
  end
end
