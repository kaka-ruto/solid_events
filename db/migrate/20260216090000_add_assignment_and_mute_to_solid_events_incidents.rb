# frozen_string_literal: true

class AddAssignmentAndMuteToSolidEventsIncidents < ActiveRecord::Migration[7.1]
  def change
    add_column :solid_events_incidents, :owner, :string
    add_column :solid_events_incidents, :team, :string
    add_column :solid_events_incidents, :muted_until, :datetime

    add_index :solid_events_incidents, :owner
    add_index :solid_events_incidents, :team
  end
end
