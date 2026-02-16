# frozen_string_literal: true

class CreateSolidEventsIncidentEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_events_incident_events do |t|
      t.references :incident, null: false, foreign_key: {to_table: :solid_events_incidents}
      t.string :action, null: false
      t.string :actor
      t.json :payload, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :solid_events_incident_events, :action
    add_index :solid_events_incident_events, :occurred_at
  end
end
