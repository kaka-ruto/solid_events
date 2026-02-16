# frozen_string_literal: true

class AddCausalLinksToSolidEvents < ActiveRecord::Migration[7.1]
  def change
    add_column :solid_events_traces, :caused_by_trace_id, :bigint
    add_column :solid_events_traces, :caused_by_event_id, :bigint
    add_index :solid_events_traces, :caused_by_trace_id
    add_index :solid_events_traces, :caused_by_event_id

    add_column :solid_events_summaries, :caused_by_trace_id, :bigint
    add_column :solid_events_summaries, :caused_by_event_id, :bigint
    add_index :solid_events_summaries, :caused_by_trace_id
    add_index :solid_events_summaries, :caused_by_event_id
  end
end
