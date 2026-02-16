# frozen_string_literal: true

class CreateSolidEventsSavedViews < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_events_saved_views do |t|
      t.string :name, null: false
      t.json :filters, default: {}
      t.string :created_by
      t.timestamps
    end

    add_index :solid_events_saved_views, :name
    add_index :solid_events_saved_views, :created_at
  end
end
