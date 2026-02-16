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

  desc "Run lightweight solid_events query benchmark"
  task :benchmark, [:sample_size] => :environment do |_task, args|
    result = SolidEvents::Benchmark.run(sample_size: args[:sample_size] || 200)
    puts result.to_json
  end
end
