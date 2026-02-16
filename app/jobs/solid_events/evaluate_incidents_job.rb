# frozen_string_literal: true

module SolidEvents
  class EvaluateIncidentsJob < ActiveJob::Base
    queue_as :default

    def perform
      SolidEvents::IncidentEvaluator.evaluate!
    end
  end
end
