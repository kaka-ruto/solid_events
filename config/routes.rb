# frozen_string_literal: true

SolidEvents::Engine.routes.draw do
  get "hot_path", to: "traces#hot_path"
  get "api/incidents", to: "api#incidents"
  get "api/incidents/:id/traces", to: "api#incident_traces", as: :api_incident_traces
  get "api/incidents/:id/context_bundle", to: "api#incident_context_bundle", as: :api_incident_context_bundle
  patch "api/incidents/:id/acknowledge", to: "api#acknowledge_incident"
  patch "api/incidents/:id/resolve", to: "api#resolve_incident"
  patch "api/incidents/:id/reopen", to: "api#reopen_incident"
  get "api/traces/:id", to: "api#trace", as: :api_trace
  get "api/traces", to: "api#traces"
  resources :incidents, only: [] do
    member do
      patch :acknowledge
      patch :resolve
      patch :reopen
    end
  end
  resources :traces, only: %i[index show], path: ""
end
