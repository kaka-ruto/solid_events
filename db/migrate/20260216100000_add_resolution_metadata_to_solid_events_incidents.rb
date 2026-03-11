# frozen_string_literal: true

class AddResolutionMetadataToSolidEventsIncidents < ActiveRecord::Migration[7.1]
  def change
    add_column :solid_events_incidents, :assigned_at, :datetime unless column_exists?(:solid_events_incidents, :assigned_at)
    add_column :solid_events_incidents, :resolved_by, :string unless column_exists?(:solid_events_incidents, :resolved_by)
    add_column :solid_events_incidents, :resolution_note, :text unless column_exists?(:solid_events_incidents, :resolution_note)

    add_index :solid_events_incidents, :assigned_at unless index_exists?(:solid_events_incidents, :assigned_at)
  end
end
