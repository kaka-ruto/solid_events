# frozen_string_literal: true

class CreateSolidEventsIncidents < ActiveRecord::Migration[7.1]
  def change
    create_table :solid_events_incidents do |t|
      t.string :kind, null: false
      t.string :severity, null: false, default: "warning"
      t.string :source
      t.string :name
      t.string :fingerprint
      t.json :payload, default: {}
      t.datetime :detected_at, null: false
      t.timestamps
    end

    add_index :solid_events_incidents, :kind
    add_index :solid_events_incidents, :severity
    add_index :solid_events_incidents, :source
    add_index :solid_events_incidents, :name
    add_index :solid_events_incidents, :fingerprint
    add_index :solid_events_incidents, :detected_at
  end
end
