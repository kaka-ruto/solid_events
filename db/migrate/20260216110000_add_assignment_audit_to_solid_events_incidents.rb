# frozen_string_literal: true

class AddAssignmentAuditToSolidEventsIncidents < ActiveRecord::Migration[7.1]
  def change
    add_column :solid_events_incidents, :assigned_by, :string unless column_exists?(:solid_events_incidents, :assigned_by)
    add_column :solid_events_incidents, :assignment_note, :text unless column_exists?(:solid_events_incidents, :assignment_note)

    add_index :solid_events_incidents, :assigned_by unless index_exists?(:solid_events_incidents, :assigned_by)
  end
end
