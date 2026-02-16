# frozen_string_literal: true

module SolidEvents
  class SavedView < Record
    self.table_name = "solid_events_saved_views"

    validates :name, presence: true

    scope :recent, -> { order(created_at: :desc) }
  end
end
