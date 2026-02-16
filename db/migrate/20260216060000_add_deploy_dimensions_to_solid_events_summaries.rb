# frozen_string_literal: true

class AddDeployDimensionsToSolidEventsSummaries < ActiveRecord::Migration[7.1]
  def change
    add_column :solid_events_summaries, :service_name, :string
    add_column :solid_events_summaries, :environment_name, :string
    add_column :solid_events_summaries, :service_version, :string
    add_column :solid_events_summaries, :deployment_id, :string
    add_column :solid_events_summaries, :region, :string

    add_index :solid_events_summaries, :service_name
    add_index :solid_events_summaries, :environment_name
    add_index :solid_events_summaries, :service_version
    add_index :solid_events_summaries, :deployment_id
    add_index :solid_events_summaries, :region
  end
end
