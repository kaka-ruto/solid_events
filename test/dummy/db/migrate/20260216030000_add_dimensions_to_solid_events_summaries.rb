# frozen_string_literal: true

class AddDimensionsToSolidEventsSummaries < ActiveRecord::Migration[7.1]
  def change
    change_table :solid_events_summaries, bulk: true do |t|
      t.string :outcome
      t.string :entity_type
      t.bigint :entity_id
      t.integer :http_status
      t.string :request_method
      t.string :path
      t.string :job_class
      t.string :queue_name
    end

    add_index :solid_events_summaries, :entity_type
    add_index :solid_events_summaries, :entity_id
    add_index :solid_events_summaries, :http_status
    add_index :solid_events_summaries, :request_method
    add_index :solid_events_summaries, :queue_name
  end
end
