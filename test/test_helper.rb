# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "dummy/config/environment"
require "rails/test_help"
require "solid_events"
require "fileutils"

ActiveJob::Base.queue_adapter = :test

storage_dir = File.expand_path("dummy/storage", __dir__)
FileUtils.mkdir_p(storage_dir)

migration_paths = [File.expand_path("dummy/db/migrate", __dir__)]
ActiveRecord::Migration.verbose = false
ActiveRecord::MigrationContext.new(migration_paths).migrate

class ActiveSupport::TestCase
  setup do
    SolidEvents::Current.reset
    SolidEvents::ErrorLink.delete_all
    SolidEvents::RecordLink.delete_all
    SolidEvents::Event.delete_all
    SolidEvents::Trace.delete_all
  end
end
