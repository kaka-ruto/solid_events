# frozen_string_literal: true

module SolidEvents
  class Record < ActiveRecord::Base
    self.abstract_class = true

    connects_to(**SolidEvents.connects_to) if SolidEvents.connects_to
  end
end

ActiveSupport.run_load_hooks :solid_events_record, SolidEvents::Record
