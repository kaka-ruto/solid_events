# frozen_string_literal: true

module SolidEvents
  class CausalEdge < Record
    self.table_name = "solid_events_causal_edges"

    validates :to_trace_id, :edge_type, :occurred_at, presence: true
  end
end
