# frozen_string_literal: true

Rails.application.routes.draw do
  mount SolidEvents::Engine, at: "/solid_events"
end
