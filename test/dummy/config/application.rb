# frozen_string_literal: true

require_relative "boot"
require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

require "solid_events"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults 7.1
    config.eager_load = false
    config.hosts.clear
    config.secret_key_base = "test"
    config.paths["config/database"] = File.expand_path("database.yml", __dir__)
    config.action_dispatch.show_exceptions = false
    config.action_controller.allow_forgery_protection = false

    config.solid_events.connects_to = {database: {writing: :primary}}
  end
end
