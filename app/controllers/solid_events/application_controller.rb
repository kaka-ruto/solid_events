# frozen_string_literal: true

module SolidEvents
  class ApplicationController < ActionController::Base
    layout "solid_events/application"
    protect_from_forgery with: :exception
  end
end
