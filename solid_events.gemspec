# frozen_string_literal: true

require_relative "lib/solid_events/version"

Gem::Specification.new do |spec|
  spec.name = "solid_events"
  spec.version = SolidEvents::VERSION
  spec.authors = ["Solid Events"]
  spec.email = ["kaka@anywaye.com"]

  spec.summary = "Database-backed context graph and tracing for Rails"
  spec.description = "SolidEvents captures controller, job, SQL, business and record-link events into a queryable trace graph."
  spec.homepage = "https://github.com/kaka-ruto/solid_events"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "README.md", "CHANGELOG.md", "Rakefile", "LICENSE.txt"]
  end

  rails_version = ">= 7.1"
  spec.add_dependency "actionpack", rails_version
  spec.add_dependency "actionview", rails_version
  spec.add_dependency "activejob", rails_version
  spec.add_dependency "activerecord", rails_version
  spec.add_dependency "activesupport", rails_version
  spec.add_dependency "railties", rails_version

  spec.add_development_dependency "sqlite3", ">= 2.0"
end
