# frozen_string_literal: true

class AddDimensionsToSolidEventsSummaries < ActiveRecord::Migration[7.1]
  def change
    add_column :solid_events_summaries, :outcome, :string unless column_exists?(:solid_events_summaries, :outcome)
    add_column :solid_events_summaries, :entity_type, :string unless column_exists?(:solid_events_summaries, :entity_type)
    add_column :solid_events_summaries, :entity_id, :bigint unless column_exists?(:solid_events_summaries, :entity_id)
    add_column :solid_events_summaries, :http_status, :integer unless column_exists?(:solid_events_summaries, :http_status)
    add_column :solid_events_summaries, :request_method, :string unless column_exists?(:solid_events_summaries, :request_method)
    add_column :solid_events_summaries, :path, :string unless column_exists?(:solid_events_summaries, :path)
    add_column :solid_events_summaries, :job_class, :string unless column_exists?(:solid_events_summaries, :job_class)
    add_column :solid_events_summaries, :queue_name, :string unless column_exists?(:solid_events_summaries, :queue_name)

    add_index :solid_events_summaries, :entity_type unless index_exists?(:solid_events_summaries, :entity_type)
    add_index :solid_events_summaries, :entity_id unless index_exists?(:solid_events_summaries, :entity_id)
    add_index :solid_events_summaries, :http_status unless index_exists?(:solid_events_summaries, :http_status)
    add_index :solid_events_summaries, :request_method unless index_exists?(:solid_events_summaries, :request_method)
    add_index :solid_events_summaries, :queue_name unless index_exists?(:solid_events_summaries, :queue_name)
  end
end
