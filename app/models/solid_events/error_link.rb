# frozen_string_literal: true

module SolidEvents
  class ErrorLink < Record
    self.table_name = "solid_events_error_links"

    belongs_to :trace, class_name: "SolidEvents::Trace"

    validates :solid_error_id, presence: true
  end
end
