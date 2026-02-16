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

  create_table :solid_events_summaries, force: :cascade do |t|
    t.references :trace, null: false, index: {unique: true}, foreign_key: {to_table: :solid_events_traces}
    t.string :name, null: false
    t.string :trace_type, null: false
    t.string :source, null: false
    t.string :status, null: false, default: "ok"
    t.string :outcome
    t.string :entity_type
    t.bigint :entity_id
    t.integer :http_status
    t.string :request_method
    t.string :request_id
    t.string :path
    t.string :job_class
    t.string :queue_name
    t.datetime :started_at, null: false
    t.datetime :finished_at
    t.float :duration_ms
    t.integer :event_count, null: false, default: 0
    t.integer :sql_count, null: false, default: 0
    t.float :sql_duration_ms, null: false, default: 0.0
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
  add_index :solid_events_summaries, :entity_type
  add_index :solid_events_summaries, :entity_id
  add_index :solid_events_summaries, :http_status
  add_index :solid_events_summaries, :request_method
  add_index :solid_events_summaries, :request_id
  add_index :solid_events_summaries, :queue_name
end
