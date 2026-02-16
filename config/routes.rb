# frozen_string_literal: true

SolidEvents::Engine.routes.draw do
  get "hot_path", to: "traces#hot_path"
  get "api/incidents", to: "api#incidents"
  get "api/incidents/:id/traces", to: "api#incident_traces", as: :api_incident_traces
  get "api/incidents/:id/context", to: "api#incident_context", as: :api_incident_context
  patch "api/incidents/:id/assign", to: "api#assign_incident"
  patch "api/incidents/:id/mute", to: "api#mute_incident"
  patch "api/incidents/:id/acknowledge", to: "api#acknowledge_incident"
  patch "api/incidents/:id/resolve", to: "api#resolve_incident"
  patch "api/incidents/:id/reopen", to: "api#reopen_incident"
  get "api/traces/:id", to: "api#trace", as: :api_trace
  get "api/traces", to: "api#traces"
  get "api/metrics/error_rates", to: "api#error_rates"
  get "api/metrics/latency", to: "api#latency"
  get "api/metrics/compare", to: "api#compare_metrics"
  get "api/metrics/cohorts", to: "api#cohort_metrics"
  resources :incidents, only: [] do
    member do
      patch :acknowledge
      patch :resolve
      patch :reopen
    end
  end
  resources :traces, only: %i[index show], path: ""
end
