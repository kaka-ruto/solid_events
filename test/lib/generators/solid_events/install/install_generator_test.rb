# frozen_string_literal: true

require "test_helper"
require "generators/solid_events/install/install_generator"
require "rails/generators/test_case"

module SolidEvents
  class InstallGeneratorTest < Rails::Generators::TestCase
    tests SolidEvents::InstallGenerator
    destination File.expand_path("../../../../tmp/generator", __dir__)

    setup do
      prepare_destination
      FileUtils.mkdir_p(File.join(destination_root, "config", "environments"))
      File.write(File.join(destination_root, "config", "environments", "production.rb"), "Rails.application.configure do\nend\n")
    end

    test "creates schema and initializer" do
      run_generator
      assert_file "db/events_schema.rb"
      assert_file "config/initializers/solid_events.rb"
      assert_file "config/environments/production.rb" do |content|
        assert_includes content, "config.solid_events.connects_to"
      end
    end
  end
end
