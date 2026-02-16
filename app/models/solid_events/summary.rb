# frozen_string_literal: true

module SolidEvents
  class Summary < Record
    self.table_name = "solid_events_summaries"

    belongs_to :trace, class_name: "SolidEvents::Trace"

    validates :trace_id, uniqueness: true
  end
end
