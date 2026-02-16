# frozen_string_literal: true

module SolidEvents
  class IncidentsController < ApplicationController
    before_action :set_incident

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
