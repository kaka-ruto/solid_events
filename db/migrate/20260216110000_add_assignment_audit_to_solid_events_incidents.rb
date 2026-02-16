# frozen_string_literal: true

class AddAssignmentAuditToSolidEventsIncidents < ActiveRecord::Migration[7.1]
  def change
    add_column :solid_events_incidents, :assigned_by, :string
    add_column :solid_events_incidents, :assignment_note, :text

    add_index :solid_events_incidents, :assigned_by
  end
end
