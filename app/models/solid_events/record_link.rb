# frozen_string_literal: true

module SolidEvents
  class RecordLink < Record
    self.table_name = "solid_events_record_links"

    belongs_to :trace, class_name: "SolidEvents::Trace"

    validates :record_type, :record_id, presence: true
  end
end
