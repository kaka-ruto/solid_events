# frozen_string_literal: true

class CreateSolidEventsJourneysAndCausalEdges < ActiveRecord::Migration[7.1]
  def change
    create_table :solid_events_journeys do |t|
      t.string :journey_key, null: false
      t.string :request_id
      t.string :entity_type
      t.bigint :entity_id
      t.bigint :last_trace_id
      t.integer :trace_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.datetime :started_at, null: false
      t.datetime :finished_at, null: false
      t.json :payload, default: {}
      t.timestamps
    end

    add_index :solid_events_journeys, :journey_key, unique: true
    add_index :solid_events_journeys, :request_id
    add_index :solid_events_journeys, [:entity_type, :entity_id]
    add_index :solid_events_journeys, :finished_at

    create_table :solid_events_causal_edges do |t|
      t.bigint :from_trace_id
      t.bigint :from_event_id
      t.bigint :to_trace_id, null: false
      t.bigint :to_event_id
      t.string :edge_type, null: false, default: "caused_by"
      t.datetime :occurred_at, null: false
      t.json :payload, default: {}
      t.timestamps
    end

    add_index :solid_events_causal_edges, :from_trace_id
    add_index :solid_events_causal_edges, :from_event_id
    add_index :solid_events_causal_edges, :to_trace_id
    add_index :solid_events_causal_edges, :occurred_at
    add_index :solid_events_causal_edges, [:from_event_id, :to_trace_id], unique: true, name: "index_solid_events_causal_edges_uniqueness"
  end
end
