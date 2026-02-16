# frozen_string_literal: true

module SolidEvents
  class ApiController < ApplicationController
    def incidents
      incidents = if incident_table_available?
        scope = SolidEvents::Incident.recent
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(kind: params[:kind]) if params[:kind].present?
        scope = scope.where(severity: params[:severity]) if params[:severity].present?
        scope.limit(limit_param)
      else
        []
      end

      render json: incidents.map { |incident| serialize_incident(incident) }
    end

    def trace
      trace = SolidEvents::Trace.includes(:summary, :events, :record_links, :error_links).find(params[:id])

      render json: {
        trace: trace.canonical_event,
        summary: trace.summary&.attributes,
        record_links: trace.record_links.map { |link| {record_type: link.record_type, record_id: link.record_id} },
        error_links: trace.error_links.map { |link| {solid_error_id: link.solid_error_id} }
      }
    end

    def traces
      scope = SolidEvents::Trace.recent
      if params[:error_fingerprint].present?
        scope = scope.left_outer_joins(:summary).where(solid_events_summaries: {error_fingerprint: params[:error_fingerprint]})
      end
      if params[:entity_type].present? || params[:entity_id].present?
        scope = scope.left_outer_joins(:summary)
        scope = scope.where("solid_events_summaries.entity_type ILIKE ?", "%#{params[:entity_type]}%") if params[:entity_type].present?
        scope = scope.where(solid_events_summaries: {entity_id: params[:entity_id].to_i}) if params[:entity_id].present?
      end

      traces = scope.includes(:summary).limit(limit_param)
      render json: traces.map { |trace| trace.canonical_event }
    end

    private

    def serialize_incident(incident)
      {
        id: incident.id,
        kind: incident.kind,
        severity: incident.severity,
        status: incident.status,
        source: incident.source,
        name: incident.name,
        fingerprint: incident.fingerprint,
        payload: incident.payload,
        detected_at: incident.detected_at,
        last_seen_at: incident.last_seen_at,
        acknowledged_at: incident.acknowledged_at,
        resolved_at: incident.resolved_at
      }
    end

    def incident_table_available?
      SolidEvents::Incident.connection.data_source_exists?(SolidEvents::Incident.table_name)
    rescue StandardError
      false
    end

    def limit_param
      return 50 if params[:limit].blank?

      [[params[:limit].to_i, 1].max, 200].min
    rescue StandardError
      50
    end
  end
end
