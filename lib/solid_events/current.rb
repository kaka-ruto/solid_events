# frozen_string_literal: true

module SolidEvents
  class Current < ActiveSupport::CurrentAttributes
    attribute :trace, :error_trace_bindings

    def error_trace_bindings
      super || {}
    end
  end
end
