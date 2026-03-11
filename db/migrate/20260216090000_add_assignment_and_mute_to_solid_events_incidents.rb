# frozen_string_literal: true

class AddAssignmentAndMuteToSolidEventsIncidents < ActiveRecord::Migration[7.1]
  def change
    add_column :solid_events_incidents, :owner, :string unless column_exists?(:solid_events_incidents, :owner)
    add_column :solid_events_incidents, :team, :string unless column_exists?(:solid_events_incidents, :team)
    add_column :solid_events_incidents, :muted_until, :datetime unless column_exists?(:solid_events_incidents, :muted_until)

    add_index :solid_events_incidents, :owner unless index_exists?(:solid_events_incidents, :owner)
    add_index :solid_events_incidents, :team unless index_exists?(:solid_events_incidents, :team)
  end
end
