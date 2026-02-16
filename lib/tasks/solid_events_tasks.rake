# frozen_string_literal: true

namespace :solid_events do
  desc "Evaluate incidents now"
  task evaluate_incidents: :environment do
    SolidEvents::EvaluateIncidentsJob.perform_now
  end

  desc "Prune retained solid_events data"
  task prune: :environment do
    SolidEvents::PruneJob.perform_now
  end
end
