# frozen_string_literal: true

module SolidEvents
  class ApiController < ApplicationController
    before_action :authenticate_api!

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

    def incident_traces
      incident = SolidEvents::Incident.find(params[:id])
      traces = incident_related_traces(incident).limit(limit_param)
      render json: {
        incident: serialize_incident(incident),
        traces: traces.map(&:canonical_event)
      }
    end

    def incident_context_bundle
      incident = SolidEvents::Incident.find(params[:id])
      traces = incident_related_traces(incident).includes(:error_links).limit(limit_param)
      error_ids = traces.flat_map { |trace| trace.error_links.map(&:solid_error_id) }.compact.uniq
      trace_query = incident.payload.to_h["trace_query"].to_h

      render json: {
        incident: serialize_incident(incident),
        evidence: {
          trace_count: traces.size,
          error_ids: error_ids,
          traces: traces.map(&:canonical_event)
        },
        suggested_filters: trace_query,
        links: {
          traces_ui: traces_path(trace_query),
          incident_traces_api: api_incident_traces_path(incident),
          incident_lifecycle: {
            acknowledge: "/solid_events/api/incidents/#{incident.id}/acknowledge",
            resolve: "/solid_events/api/incidents/#{incident.id}/resolve",
            reopen: "/solid_events/api/incidents/#{incident.id}/reopen"
          }
        }
      }
    end

    def acknowledge_incident
      incident = SolidEvents::Incident.find(params[:id])
      incident.acknowledge!
      render json: serialize_incident(incident)
    end

    def assign_incident
      incident = SolidEvents::Incident.find(params[:id])
      incident.update!(owner: params[:owner].presence, team: params[:team].presence)
      render json: serialize_incident(incident)
    end

    def mute_incident
      incident = SolidEvents::Incident.find(params[:id])
      minutes = params[:minutes].to_i
      minutes = 60 if minutes <= 0
      incident.mute_for!(minutes.minutes)
      render json: serialize_incident(incident)
    end

    def resolve_incident
      incident = SolidEvents::Incident.find(params[:id])
      incident.resolve!
      render json: serialize_incident(incident)
    end

    def reopen_incident
      incident = SolidEvents::Incident.find(params[:id])
      incident.reopen!
      render json: serialize_incident(incident)
    end

    def incident_handoff
      incident = SolidEvents::Incident.find(params[:id])
      traces = incident_related_traces(incident).includes(:error_links, :summary).limit(limit_param)
      primary_trace = traces.first

      render json: {
        goal: "Investigate and fix #{incident.kind} for #{incident.source}/#{incident.name}",
        incident: serialize_incident(incident),
        evidence: {
          trace_count: traces.size,
          primary_trace: primary_trace&.canonical_event,
          trace_ids: traces.map(&:id),
          error_ids: traces.flat_map { |trace| trace.error_links.map(&:solid_error_id) }.uniq
        },
        constraints: {
          schema_version: SolidEvents.canonical_schema_version,
          keep_regression_tests_green: true,
          avoid_sensitive_data: true
        },
        next_actions: [
          "Reproduce from primary trace/request context",
          "Add or update a focused failing test",
          "Implement minimal fix",
          "Run targeted tests then full suite",
          "Update incident status to resolved when verified"
        ],
        hints: {
          suspected_files: suspect_files_for(incident: incident, trace: primary_trace),
          suggested_commands: suggested_commands_for(incident: incident)
        }
      }
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
        owner: incident.owner,
        team: incident.team,
        source: incident.source,
        name: incident.name,
        fingerprint: incident.fingerprint,
        payload: incident.payload,
        detected_at: incident.detected_at,
        last_seen_at: incident.last_seen_at,
        acknowledged_at: incident.acknowledged_at,
        resolved_at: incident.resolved_at,
        muted_until: incident.muted_until
      }
    end

    def suspect_files_for(incident:, trace:)
      files = []
      if incident.source.to_s.include?("#")
        controller = incident.source.to_s.split("#").first.underscore
        files << "app/controllers/#{controller}.rb"
        files << "test/controllers/#{controller}_test.rb"
      end
      if trace&.summary&.entity_type.present?
        model_name = trace.summary.entity_type.to_s.underscore
        files << "app/models/#{model_name}.rb"
      end
      files.uniq
    end

    def suggested_commands_for(incident:)
      commands = []
      if incident.source.to_s.include?("#")
        controller = incident.source.to_s.split("#").first.underscore
        commands << "bin/rails test test/controllers/#{controller}_test.rb"
      end
      commands << "bin/rails test"
      commands
    end

    def incident_related_traces(incident)
      scope = SolidEvents::Trace.recent.includes(:summary)
      query = incident.payload.to_h["trace_query"].to_h
      trace_ids = Array(incident.payload.to_h["trace_ids"]).map(&:to_i).uniq

      if trace_ids.any?
        return scope.where(id: trace_ids)
      end

      if query["error_fingerprint"].present?
        scope = scope.left_outer_joins(:summary).where(solid_events_summaries: {error_fingerprint: query["error_fingerprint"]})
      end
      if query["name"].present?
        scope = scope.where(name: query["name"])
      end
      if query["source"].present?
        scope = scope.where(source: query["source"])
      end
      if query["entity_type"].present? || query["entity_id"].present?
        scope = scope.left_outer_joins(:summary)
        scope = scope.where(solid_events_summaries: {entity_type: query["entity_type"]}) if query["entity_type"].present?
        scope = scope.where(solid_events_summaries: {entity_id: query["entity_id"].to_i}) if query["entity_id"].present?
      end

      scope
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

    def authenticate_api!
      token = SolidEvents.api_token.to_s
      return if token.blank?

      presented = request.headers["X-Solid-Events-Token"].to_s
      auth_header = request.headers["Authorization"].to_s
      bearer = auth_header.start_with?("Bearer ") ? auth_header.delete_prefix("Bearer ").strip : ""
      return if ActiveSupport::SecurityUtils.secure_compare(presented, token)
      return if ActiveSupport::SecurityUtils.secure_compare(bearer, token)

      render json: {error: "unauthorized"}, status: :unauthorized
    rescue StandardError
      render json: {error: "unauthorized"}, status: :unauthorized
    end
  end
end
