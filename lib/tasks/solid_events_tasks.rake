# frozen_string_literal: true
require "fileutils"

namespace :solid_events do
  namespace :install do
    desc "Copy solid_events engine migrations into db/events_migrate"
    task :events_migrations do
      source_dir = SolidEvents::Engine.root.join("db/migrate").to_s
      destination_dir = File.expand_path("db/events_migrate", Dir.pwd)
      FileUtils.mkdir_p(destination_dir)

      copied = []
      Dir.glob(File.join(source_dir, "*.rb")).sort.each do |source_path|
        filename = File.basename(source_path)
        destination_path = File.join(destination_dir, filename)
        next if File.exist?(destination_path)

        FileUtils.cp(source_path, destination_path)
        copied << filename
      end

      if copied.empty?
        puts "No new solid_events migrations to copy."
      else
        puts "Copied solid_events migrations:"
        copied.each { |filename| puts "  - #{filename}" }
      end
    end
  end

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

  desc "Run benchmark and enforce warn/fail thresholds in ms"
  task :benchmark_check, [:sample_size, :warn_ms, :fail_ms] => :environment do |_task, args|
    result = SolidEvents::Benchmark.run(sample_size: args[:sample_size] || 200)
    evaluation = SolidEvents::Benchmark.evaluate(
      result: result,
      warn_ms: args[:warn_ms] || 150,
      fail_ms: args[:fail_ms] || 250
    )
    puts result.merge(evaluation: evaluation).to_json
    abort("solid_events benchmark failed threshold") if evaluation[:status] == "fail"
  end
end
