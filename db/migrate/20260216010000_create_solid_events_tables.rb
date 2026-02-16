# frozen_string_literal: true

class CreateSolidEventsTables < ActiveRecord::Migration[7.1]
  def change
    unless table_exists?(:solid_events_traces)
      create_table :solid_events_traces do |t|
        t.string :name, null: false
        t.string :trace_type, null: false
        t.string :source, null: false
        t.string :status, null: false, default: "ok"
        t.json :context, default: {}
        t.datetime :started_at, null: false
        t.datetime :finished_at
        t.timestamps
      end
    end

    unless table_exists?(:solid_events_events)
      create_table :solid_events_events do |t|
        t.references :trace, null: false, foreign_key: {to_table: :solid_events_traces}
        t.string :event_type, null: false
        t.string :name, null: false
        t.float :duration_ms
        t.json :payload, default: {}
        t.datetime :occurred_at, null: false
        t.timestamps
      end
    end

    unless table_exists?(:solid_events_record_links)
      create_table :solid_events_record_links do |t|
        t.references :trace, null: false, foreign_key: {to_table: :solid_events_traces}
        t.string :record_type, null: false
        t.bigint :record_id, null: false
        t.timestamps
      end
    end
    unless index_exists?(:solid_events_record_links, [:trace_id, :record_type, :record_id], unique: true, name: "index_solid_events_record_links_uniqueness")
      add_index :solid_events_record_links, [:trace_id, :record_type, :record_id], unique: true, name: "index_solid_events_record_links_uniqueness"
    end

    unless table_exists?(:solid_events_error_links)
      create_table :solid_events_error_links do |t|
        t.references :trace, null: false, foreign_key: {to_table: :solid_events_traces}
        t.bigint :solid_error_id, null: false
        t.timestamps
      end
    end
    add_index :solid_events_error_links, [:trace_id, :solid_error_id], unique: true unless index_exists?(:solid_events_error_links, [:trace_id, :solid_error_id], unique: true)
  end
end
