# frozen_string_literal: true

SolidEvents::Engine.routes.draw do
  get "hot_path", to: "traces#hot_path"
  resources :incidents, only: [] do
    member do
      patch :acknowledge
      patch :resolve
      patch :reopen
    end
  end
  resources :traces, only: %i[index show], path: ""
end
