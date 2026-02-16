# frozen_string_literal: true

class AddIncidentEventLookupIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :solid_events_incident_events, [:incident_id, :occurred_at], name: "index_solid_events_incident_events_on_incident_and_time"
    add_index :solid_events_incident_events, [:incident_id, :action, :occurred_at], name: "index_solid_events_incident_events_on_incident_action_time"
  end
end
