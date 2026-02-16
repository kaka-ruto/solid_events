# frozen_string_literal: true

SolidEvents::Engine.routes.draw do
  get "hot_path", to: "traces#hot_path"
  resources :traces, only: %i[index show], path: ""
end
