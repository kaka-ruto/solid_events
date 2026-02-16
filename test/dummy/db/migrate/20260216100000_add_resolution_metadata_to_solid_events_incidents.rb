# frozen_string_literal: true

class AddResolutionMetadataToSolidEventsIncidents < ActiveRecord::Migration[7.1]
  def change
    add_column :solid_events_incidents, :assigned_at, :datetime
    add_column :solid_events_incidents, :resolved_by, :string
    add_column :solid_events_incidents, :resolution_note, :text

    add_index :solid_events_incidents, :assigned_at
  end
end
