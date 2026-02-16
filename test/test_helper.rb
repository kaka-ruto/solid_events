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
    if defined?(SolidEvents::Incident) && SolidEvents::Incident.connection.data_source_exists?(SolidEvents::Incident.table_name)
      SolidEvents::Incident.delete_all
    end
    if defined?(SolidEvents::Summary) && SolidEvents::Summary.connection.data_source_exists?(SolidEvents::Summary.table_name)
      SolidEvents::Summary.delete_all
    end
    if defined?(SolidEvents::SavedView) && SolidEvents::SavedView.connection.data_source_exists?(SolidEvents::SavedView.table_name)
      SolidEvents::SavedView.delete_all
    end
    if defined?(SolidEvents::IncidentEvent) && SolidEvents::IncidentEvent.connection.data_source_exists?(SolidEvents::IncidentEvent.table_name)
      SolidEvents::IncidentEvent.delete_all
    end
    SolidEvents::ErrorLink.delete_all
    SolidEvents::RecordLink.delete_all
    SolidEvents::Event.delete_all
    SolidEvents::Trace.delete_all
  end
end
