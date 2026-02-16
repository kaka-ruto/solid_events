# frozen_string_literal: true

module SolidEvents
  class PruneJob < ActiveJob::Base
    queue_as :default

    def perform
      cutoff = SolidEvents.retention_period.ago
      SolidEvents::Trace.where("started_at < ?", cutoff).delete_all
    end
  end
end
