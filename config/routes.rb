# frozen_string_literal: true

SolidEvents::Engine.routes.draw do
  get "hot_path", to: "traces#hot_path"
  get "timeline", to: "traces#timeline"
  get "api/incidents", to: "api#incidents"
  get "api/incidents/:id/traces", to: "api#incident_traces", as: :api_incident_traces
  get "api/incidents/:id/context", to: "api#incident_context", as: :api_incident_context
  get "api/incidents/:id/evidence_slices", to: "api#incident_evidence_slices", as: :api_incident_evidence_slices
  get "api/incidents/:id/events", to: "api#incident_events", as: :api_incident_events
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
  get "api/journeys", to: "api#journeys"
  get "api/export/traces", to: "api#export_traces"
  get "api/export/incidents", to: "api#export_incidents"
  resources :saved_views, only: %i[create destroy]
  resources :incidents, only: [] do
    member do
      get :events
      patch :acknowledge
      patch :resolve
      patch :reopen
    end
  end
  resources :traces, only: %i[index show], path: ""
end
