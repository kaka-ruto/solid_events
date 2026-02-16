# frozen_string_literal: true

class AddRequestIdToSolidEventsSummaries < ActiveRecord::Migration[7.1]
  def change
    add_column :solid_events_summaries, :request_id, :string
    add_index :solid_events_summaries, :request_id
  end
end
