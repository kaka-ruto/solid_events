# frozen_string_literal: true

module SolidEvents
  class IncidentsController < ApplicationController
    before_action :set_incident

    def events
      @event_action = params[:event_action].to_s
      @cursor = params[:cursor].to_i
      @events = @incident.incident_events.recent
      @events = @events.where(action: @event_action) if @event_action.present?
      @events = @events.where("id < ?", @cursor) if @cursor.positive?
      @events = @events.limit(50)
      @next_cursor = @events.last&.id
    end

    def acknowledge
      @incident.acknowledge!
      redirect_back fallback_location: traces_path
    end

    def resolve
      @incident.resolve!
      redirect_back fallback_location: traces_path
    end

    def reopen
      @incident.reopen!
      redirect_back fallback_location: traces_path
    end

    private

    def set_incident
      @incident = SolidEvents::Incident.find(params[:id])
    end
  end
end
