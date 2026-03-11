# frozen_string_literal: true

class AddDeployDimensionsToSolidEventsSummaries < ActiveRecord::Migration[7.1]
  def change
    add_column :solid_events_summaries, :service_name, :string unless column_exists?(:solid_events_summaries, :service_name)
    add_column :solid_events_summaries, :environment_name, :string unless column_exists?(:solid_events_summaries, :environment_name)
    add_column :solid_events_summaries, :service_version, :string unless column_exists?(:solid_events_summaries, :service_version)
    add_column :solid_events_summaries, :deployment_id, :string unless column_exists?(:solid_events_summaries, :deployment_id)
    add_column :solid_events_summaries, :region, :string unless column_exists?(:solid_events_summaries, :region)

    add_index :solid_events_summaries, :service_name unless index_exists?(:solid_events_summaries, :service_name)
    add_index :solid_events_summaries, :environment_name unless index_exists?(:solid_events_summaries, :environment_name)
    add_index :solid_events_summaries, :service_version unless index_exists?(:solid_events_summaries, :service_version)
    add_index :solid_events_summaries, :deployment_id unless index_exists?(:solid_events_summaries, :deployment_id)
    add_index :solid_events_summaries, :region unless index_exists?(:solid_events_summaries, :region)
  end
end
