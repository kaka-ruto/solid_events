# frozen_string_literal: true

SolidEvents::Engine.routes.draw do
  resources :traces, only: %i[index show], path: ""
end
