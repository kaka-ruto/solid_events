# frozen_string_literal: true

module SolidEvents
  class InstallGenerator < Rails::Generators::Base
    source_root File.expand_path("templates", __dir__)

    def add_schema
      template "db/events_schema.rb"
    end

    def add_initializer
      template "config/initializers/solid_events.rb"
    end

    def configure_production
      insert_into_file Pathname(destination_root).join("config/environments/production.rb"), after: /^([ \t]*).*?(?=\nend)$/ do
        [
          "",
          '\\1# Configure Solid Events',
          '\\1config.solid_events.connects_to = { database: { writing: :solid_events } }'
        ].join("\n")
      end
    end

    def ensure_migrations_directory
      empty_directory "db/events_migrate"
      keep_path = Pathname(destination_root).join("db/events_migrate/.gitkeep")
      return if keep_path.exist?

      create_file "db/events_migrate/.gitkeep", "# Keep the SolidEvents migrations directory tracked by Git.\n"
    end
  end
end
