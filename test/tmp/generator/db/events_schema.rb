# frozen_string_literal: true

ActiveRecord::Schema[7.1].define do
  create_table :solid_events_traces, force: :cascade do |t|
    t.string :name, null: false
    t.string :trace_type, null: false
    t.string :source, null: false
    t.string :status, null: false, default: "ok"
    t.json :context, default: {}
    t.datetime :started_at, null: false
    t.datetime :finished_at
    t.timestamps
  end

  add_index :solid_events_traces, :started_at
  add_index :solid_events_traces, :trace_type
  add_index :solid_events_traces, :status

  create_table :solid_events_events, force: :cascade do |t|
    t.references :trace, null: false, foreign_key: {to_table: :solid_events_traces}
    t.string :event_type, null: false
    t.string :name, null: false
    t.float :duration_ms
    t.json :payload, default: {}
    t.datetime :occurred_at, null: false
    t.timestamps
  end

  add_index :solid_events_events, :event_type
  add_index :solid_events_events, :occurred_at

  create_table :solid_events_record_links, force: :cascade do |t|
    t.references :trace, null: false, foreign_key: {to_table: :solid_events_traces}
    t.string :record_type, null: false
    t.bigint :record_id, null: false
    t.timestamps
  end

  add_index :solid_events_record_links, [:trace_id, :record_type, :record_id], unique: true, name: "index_solid_events_record_links_uniqueness"
  add_index :solid_events_record_links, [:record_type, :record_id]

  create_table :solid_events_error_links, force: :cascade do |t|
    t.references :trace, null: false, foreign_key: {to_table: :solid_events_traces}
    t.bigint :solid_error_id, null: false
    t.timestamps
  end

  add_index :solid_events_error_links, [:trace_id, :solid_error_id], unique: true
end
