# frozen_string_literal: true

require_relative "tracer"
require_relative "labeler"
require_relative "context_scraper"
require_relative "controller_tracing"
require_relative "incident_evaluator"
require_relative "notifiers/slack_webhook_notifier"
require_relative "subscribers/sql_subscriber"
require_relative "subscribers/enqueue_subscriber"
require_relative "subscribers/job_subscriber"
require_relative "subscribers/action_cable_subscriber"
require_relative "subscribers/mailer_subscriber"
require_relative "subscribers/external_http_subscriber"
require_relative "subscribers/error_subscriber"

module SolidEvents
  class Engine < ::Rails::Engine
    isolate_namespace SolidEvents

    config.root = File.expand_path("../..", __dir__)
    config.solid_events = ActiveSupport::OrderedOptions.new

    initializer "solid_events.configure" do
      config.solid_events.each do |name, value|
        SolidEvents.configuration.public_send(:"#{name}=", value)
      end
    end

    initializer "solid_events.subscribers" do
      sql_subscriber = SolidEvents::Subscribers::SqlSubscriber.new
      enqueue_subscriber = SolidEvents::Subscribers::EnqueueSubscriber.new
      job_subscriber = SolidEvents::Subscribers::JobSubscriber.new
      cable_subscriber = SolidEvents::Subscribers::ActionCableSubscriber.new
      mailer_subscriber = SolidEvents::Subscribers::MailerSubscriber.new
      external_http_subscriber = SolidEvents::Subscribers::ExternalHttpSubscriber.new

      ActiveSupport::Notifications.subscribe("sql.active_record", sql_subscriber)
      ActiveSupport::Notifications.subscribe("enqueue.active_job", enqueue_subscriber)
      ActiveSupport::Notifications.subscribe("enqueue_at.active_job", enqueue_subscriber)
      ActiveSupport::Notifications.subscribe("perform.active_job", job_subscriber)
      ActiveSupport::Notifications.subscribe("perform_action.action_cable", cable_subscriber)
      ActiveSupport::Notifications.subscribe("process.action_mailer", mailer_subscriber)
      ActiveSupport::Notifications.subscribe("request.faraday", external_http_subscriber)
      ActiveSupport::Notifications.subscribe("request.http", external_http_subscriber)
      ActiveSupport::Notifications.subscribe("http.client", external_http_subscriber)
      Rails.error.subscribe(SolidEvents::Subscribers::ErrorSubscriber.new)
    end

    initializer "solid_events.controller_tracing" do
      ActiveSupport.on_load(:action_controller_base) do
        next if defined?(::SolidEventsControllerTracingInstalled)

        include SolidEvents::ControllerTracing
        ::SolidEventsControllerTracingInstalled = true
      end
    end

    initializer "solid_events.record_linking" do
      ActiveSupport.on_load(:active_record) do
        next if defined?(SolidEvents::RecordObserverInstalled)

        module ::SolidEventsRecordLinking
          def _create_record(*args, &block)
            super.tap { SolidEvents::Tracer.link_record!(self) }
          end

          def _update_record(*args, &block)
            super.tap { |ok| SolidEvents::Tracer.link_record!(self) if ok }
          end
        end

        ActiveRecord::Base.prepend(::SolidEventsRecordLinking)
        ::SolidEventsRecordObserverInstalled = true
      end
    end
  end
end
