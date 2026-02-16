# frozen_string_literal: true

module SolidEvents
  class Current < ActiveSupport::CurrentAttributes
    attribute :trace, :error_trace_bindings, :trace_metrics

    def error_trace_bindings
      super || {}
    end

    def trace_metrics
      super || {}
    end
  end
end
