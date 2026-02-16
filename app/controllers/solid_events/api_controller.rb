# frozen_string_literal: true

module SolidEvents
  class ApiController < ApplicationController
    before_action :authenticate_api!

    def incidents
      incidents = if incident_table_available?
        scope = SolidEvents::Incident.order(id: :desc)
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(kind: params[:kind]) if params[:kind].present?
        scope = scope.where(severity: params[:severity]) if params[:severity].present?
        scope = apply_cursor(scope)
        scope.limit(limit_param)
      else
        []
      end

      render json: {
        data: incidents.map { |incident| serialize_incident(incident) },
        next_cursor: incidents.last&.id
      }
    end

    def incident_traces
      incident = SolidEvents::Incident.find(params[:id])
      traces = incident_related_traces(incident).limit(limit_param)
      render json: {
        incident: serialize_incident(incident),
        traces: traces.map(&:canonical_event)
      }
    end

    def incident_context
      incident = SolidEvents::Incident.find(params[:id])
      render json: context_payload_for(incident)
    end

    def incident_events
      incident = SolidEvents::Incident.find(params[:id])
      events = incident.incident_events.recent.limit(limit_param)
      events = events.where(action: params[:event_action].to_s) if params[:event_action].present?
      events = apply_cursor(events)
      render json: {
        incident: serialize_incident(incident),
        data: events.map { |event| serialize_incident_event(event) },
        next_cursor: events.last&.id
      }
    end

    def incident_evidences
      incident = SolidEvents::Incident.find(params[:id])
      traces = incident_related_traces(incident).includes(:summary).limit(2_000)
      summaries = traces.map(&:summary).compact

      by_source = summaries.group_by(&:source).transform_values(&:size).sort_by { |_, count| -count }.first(10).to_h
      by_status = summaries.group_by(&:status).transform_values(&:size)
      by_entity = summaries
        .map { |summary| [summary.entity_type, summary.entity_id] }
        .reject { |type, id| type.blank? || id.blank? }
        .tally
        .sort_by { |(_, count)| -count }
        .first(10)
        .map { |(type, id), count| {entity_type: type, entity_id: id, count: count} }

      render json: {
        incident: serialize_incident(incident),
        evidences: {
          by_source: by_source,
          by_status: by_status,
          by_entity: by_entity,
          duration_ms: duration_slice_for(summaries),
          error_rate_pct: error_rate_for(summaries)
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
      incident.assign!(
        owner: params[:owner].presence,
        team: params[:team].presence,
        assigned_by: params[:assigned_by].presence,
        assignment_note: params[:assignment_note].presence
      )
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
      if params[:resolved_by].present? || params[:resolution_note].present?
        incident.resolve_with!(resolved_by: params[:resolved_by].presence || "system", resolution_note: params[:resolution_note].presence)
      else
        incident.resolve!
      end
      render json: serialize_incident(incident)
    end

    def reopen_incident
      incident = SolidEvents::Incident.find(params[:id])
      incident.reopen!
      render json: serialize_incident(incident)
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
      scope = SolidEvents::Trace.order(id: :desc)
      if params[:error_fingerprint].present?
        scope = scope.left_outer_joins(:summary).where(solid_events_summaries: {error_fingerprint: params[:error_fingerprint]})
      end
      if params[:entity_type].present? || params[:entity_id].present?
        scope = scope.left_outer_joins(:summary)
        scope = scope.where("solid_events_summaries.entity_type ILIKE ?", "%#{params[:entity_type]}%") if params[:entity_type].present?
        scope = scope.where(solid_events_summaries: {entity_id: params[:entity_id].to_i}) if params[:entity_id].present?
      end
      scope = apply_feature_slice_filter(scope)

      scope = apply_cursor(scope)
      traces = scope.includes(:summary).limit(limit_param)
      render json: {
        data: traces.map { |trace| trace.canonical_event },
        next_cursor: traces.last&.id
      }
    end

    def error_rates
      dimension = metric_dimension_param
      groups = summary_scope_for_metrics
        .group(dimension)
        .order(Arel.sql("COUNT(*) DESC"))
        .limit(limit_param)
        .count

      data = groups.map do |value, total|
        scoped = summary_scope_for_metrics.where(dimension => value)
        error_count = scoped.where(status: "error").count
        {
          dimension: dimension,
          value: value,
          total_count: total,
          error_count: error_count,
          error_rate_pct: total.positive? ? ((error_count.to_f / total) * 100.0).round(2) : 0.0
        }
      end

      render json: {window: metric_window_param, dimension: dimension, groups: data}
    end

    def latency
      dimension = metric_dimension_param
      groups = summary_scope_for_metrics
        .where.not(duration_ms: nil)
        .group(dimension)
        .order(Arel.sql("COUNT(*) DESC"))
        .limit(limit_param)
        .pluck(
          dimension,
          Arel.sql("COUNT(*)"),
          Arel.sql("AVG(duration_ms)"),
          Arel.sql("MAX(duration_ms)")
        )

      data = groups.map do |value, total_count, avg_duration, max_duration|
        {
          dimension: dimension,
          value: value,
          sample_count: total_count.to_i,
          avg_duration_ms: avg_duration.to_f.round(2),
          max_duration_ms: max_duration.to_f.round(2)
        }
      end

      render json: {window: metric_window_param, dimension: dimension, groups: data}
    end

    def compare_metrics
      dimension = metric_dimension_param
      metric = metric_param
      windows = metric_compare_windows

      scoped = summary_scope_base_for_metrics
      current_stats = grouped_metric_stats(scope: scoped.where(started_at: windows[:current_start]..windows[:current_end]), dimension: dimension)
      baseline_stats = grouped_metric_stats(scope: scoped.where(started_at: windows[:baseline_start]..windows[:baseline_end]), dimension: dimension)
      values = (current_stats.keys + baseline_stats.keys).uniq

      groups = values.map do |value|
        current = current_stats.fetch(value, default_metric_stats)
        baseline = baseline_stats.fetch(value, default_metric_stats)
        current_value = metric_value_for(metric, current)
        baseline_value = metric_value_for(metric, baseline)
        delta = (current_value - baseline_value).round(2)

        {
          dimension: dimension,
          value: value,
          metric: metric,
          current: current_value,
          baseline: baseline_value,
          delta: delta,
          delta_pct: percent_delta(current_value, baseline_value),
          current_sample_count: current[:total_count],
          baseline_sample_count: baseline[:total_count]
        }
      end.sort_by { |row| [-row[:current_sample_count].to_i, row[:value].to_s] }

      render json: {
        dimension: dimension,
        metric: metric,
        current_window: windows[:current_window],
        baseline_window: windows[:baseline_window],
        groups: groups.first(limit_param)
      }
    end

    def cohort_metrics
      return render json: {error: "cohort_key is required"}, status: :unprocessable_entity if params[:cohort_key].blank?

      metric = metric_param
      cohort_key = params[:cohort_key].to_s
      requested_values = params[:cohort_values].to_s.split(",").map(&:strip).reject(&:blank?)

      rows = summary_scope_for_metrics.limit(10_000).pluck(:status, :duration_ms, :payload)
      grouped = Hash.new { |hash, key| hash[key] = {count: 0, error_count: 0, latency_sum: 0.0} }

      rows.each do |status, duration_ms, payload|
        context = payload.to_h["context"].to_h
        cohort_value = context[cohort_key]
        next if cohort_value.blank?

        cohort_value = cohort_value.to_s
        next if requested_values.any? && !requested_values.include?(cohort_value)

        grouped[cohort_value][:count] += 1
        grouped[cohort_value][:error_count] += 1 if status == "error"
        grouped[cohort_value][:latency_sum] += duration_ms.to_f
      end

      groups = grouped.map do |cohort_value, stats|
        value = if metric == "latency_avg"
          stats[:count].positive? ? (stats[:latency_sum] / stats[:count]).round(2) : 0.0
        else
          stats[:count].positive? ? ((stats[:error_count].to_f / stats[:count]) * 100.0).round(2) : 0.0
        end

        {
          cohort_key: cohort_key,
          cohort_value: cohort_value,
          metric: metric,
          value: value,
          sample_count: stats[:count],
          error_count: stats[:error_count]
        }
      end.sort_by { |row| [-row[:sample_count], row[:cohort_value]] }

      render json: {
        window: metric_window_param,
        cohort_key: cohort_key,
        metric: metric,
        groups: groups.first(limit_param)
      }
    end

    def journeys
      scope = summary_scope_for_metrics
      scope = scope.where(request_id: params[:request_id].to_s) if params[:request_id].present?
      if params[:entity_type].present?
        scope = scope.where(entity_type: params[:entity_type].to_s)
      end
      if params[:entity_id].present?
        scope = scope.where(entity_id: params[:entity_id].to_i)
      end
      scope = scope.where(status: "error") if errors_only_param?

      traces_per_journey = [[params[:traces_per_journey].to_i, 1].max, 50].min
      traces_per_journey = 20 if params[:traces_per_journey].blank?
      rows = scope.includes(:trace).order(started_at: :desc).limit(2_000).to_a
      grouped = rows.group_by { |summary| journey_key_for(summary) }.reject { |key, _| key.blank? }

      journeys = grouped.map do |key, summaries|
        ordered = summaries.sort_by(&:started_at)
        traces = ordered.last(traces_per_journey).map { |summary| summary.trace.canonical_event }
        {
          journey_key: key,
          request_id: ordered.last.request_id,
          entity_type: ordered.last.entity_type,
          entity_id: ordered.last.entity_id,
          trace_count: summaries.size,
          error_count: summaries.count { |summary| summary.status == "error" },
          started_at: ordered.first.started_at,
          finished_at: ordered.last.finished_at || ordered.last.started_at,
          traces: traces
        }
      end

      sorted = journeys.sort_by { |journey| journey[:finished_at] || Time.at(0) }.reverse.first(limit_param)
      render json: {window: metric_window_param, errors_only: errors_only_param?, journeys: sorted}
    end

    def materialized_journeys
      return render json: {data: [], next_cursor: nil} unless journey_table_available?

      scope = SolidEvents::Journey.order(id: :desc)
      scope = scope.where(request_id: params[:request_id].to_s) if params[:request_id].present?
      if params[:entity_type].present?
        scope = scope.where(entity_type: params[:entity_type].to_s)
      end
      if params[:entity_id].present?
        scope = scope.where(entity_id: params[:entity_id].to_i)
      end
      scope = apply_cursor(scope)
      rows = scope.limit(limit_param)

      render json: {
        data: rows.map { |row| serialize_materialized_journey(row) },
        next_cursor: rows.last&.id
      }
    end

    def causal_edges
      return render json: {data: [], next_cursor: nil} unless causal_edges_table_available?

      scope = SolidEvents::CausalEdge.order(id: :desc)
      if params[:trace_id].present?
        trace_id = params[:trace_id].to_i
        scope = scope.where("from_trace_id = ? OR to_trace_id = ?", trace_id, trace_id)
      end
      scope = scope.where(edge_type: params[:edge_type].to_s) if params[:edge_type].present?
      scope = apply_cursor(scope)
      rows = scope.limit(limit_param)

      render json: {
        data: rows.map { |row| serialize_causal_edge(row) },
        next_cursor: rows.last&.id
      }
    end

    def export_traces
      return render json: {error: "only json export is supported"}, status: :unprocessable_entity unless export_json?

      scope = SolidEvents::Trace.order(id: :desc)
      scope = scope.where(status: params[:status]) if params[:status].in?(%w[ok error])
      scope = scope.where("started_at >= ?", window_start_for_metrics) if params[:window].present?
      scope = scope.left_outer_joins(:summary).where(solid_events_summaries: {error_fingerprint: params[:error_fingerprint]}) if params[:error_fingerprint].present?
      if params[:entity_type].present? || params[:entity_id].present?
        scope = scope.left_outer_joins(:summary)
        scope = scope.where("solid_events_summaries.entity_type ILIKE ?", "%#{params[:entity_type]}%") if params[:entity_type].present?
        scope = scope.where(solid_events_summaries: {entity_id: params[:entity_id].to_i}) if params[:entity_id].present?
      end
      scope = apply_feature_slice_filter(scope)
      scope = apply_cursor(scope)

      traces = scope.includes(:summary).limit(limit_param)
      render json: {
        exported_at: Time.current.iso8601,
        format: "json",
        filters: export_filters_payload,
        data: traces.map(&:canonical_event)
      }
    end

    def export_incidents
      return render json: {error: "only json export is supported"}, status: :unprocessable_entity unless export_json?

      scope = SolidEvents::Incident.order(id: :desc)
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.where(kind: params[:kind]) if params[:kind].present?
      scope = scope.where(severity: params[:severity]) if params[:severity].present?
      scope = scope.where("detected_at >= ?", window_start_for_metrics) if params[:window].present?
      scope = apply_cursor(scope)
      incidents = scope.limit(limit_param)

      render json: {
        exported_at: Time.current.iso8601,
        format: "json",
        filters: export_filters_payload,
        data: incidents.map { |incident| serialize_incident(incident) }
      }
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
        assigned_by: incident.assigned_by,
        assignment_note: incident.assignment_note,
        assigned_at: incident.assigned_at,
        source: incident.source,
        name: incident.name,
        fingerprint: incident.fingerprint,
        payload: incident.payload,
        detected_at: incident.detected_at,
        last_seen_at: incident.last_seen_at,
        acknowledged_at: incident.acknowledged_at,
        resolved_at: incident.resolved_at,
        resolved_by: incident.resolved_by,
        resolution_note: incident.resolution_note,
        muted_until: incident.muted_until
      }
    end

    def serialize_incident_event(event)
      {
        id: event.id,
        incident_id: event.incident_id,
        action: event.action,
        actor: event.actor,
        payload: event.payload,
        occurred_at: event.occurred_at
      }
    end

    def serialize_materialized_journey(journey)
      {
        id: journey.id,
        journey_key: journey.journey_key,
        request_id: journey.request_id,
        entity_type: journey.entity_type,
        entity_id: journey.entity_id,
        last_trace_id: journey.last_trace_id,
        trace_count: journey.trace_count,
        error_count: journey.error_count,
        started_at: journey.started_at,
        finished_at: journey.finished_at,
        payload: journey.payload
      }
    end

    def serialize_causal_edge(edge)
      {
        id: edge.id,
        from_trace_id: edge.from_trace_id,
        from_event_id: edge.from_event_id,
        to_trace_id: edge.to_trace_id,
        to_event_id: edge.to_event_id,
        edge_type: edge.edge_type,
        occurred_at: edge.occurred_at,
        payload: edge.payload
      }
    end

    def context_payload_for(incident)
      traces = incident_related_traces(incident).includes(:error_links).limit(limit_param)
      error_ids = traces.flat_map { |trace| trace.error_links.map(&:solid_error_id) }.compact.uniq
      trace_query = incident.payload.to_h["trace_query"].to_h

      {
        incident: serialize_incident(incident),
        evidence: {
          trace_count: traces.size,
          error_ids: error_ids,
          traces: traces.map(&:canonical_event),
          solid_errors: fetch_solid_errors(error_ids)
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

    def journey_table_available?
      SolidEvents::Journey.connection.data_source_exists?(SolidEvents::Journey.table_name)
    rescue StandardError
      false
    end

    def causal_edges_table_available?
      SolidEvents::CausalEdge.connection.data_source_exists?(SolidEvents::CausalEdge.table_name)
    rescue StandardError
      false
    end

    def limit_param
      return 50 if params[:limit].blank?

      [[params[:limit].to_i, 1].max, 200].min
    rescue StandardError
      50
    end

    def apply_cursor(scope)
      cursor = params[:cursor].to_i
      return scope if cursor <= 0

      scope.where("id < ?", cursor)
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

    def fetch_solid_errors(error_ids)
      return [] if error_ids.empty?
      return [] unless defined?(SolidErrors::Error)

      errors = SolidErrors::Error.where(id: error_ids)
      errors.map do |error|
        occurrences_count = if error.respond_to?(:occurrences)
          error.occurrences.count
        else
          nil
        end
        {
          id: error.id,
          exception_class: error.try(:exception_class),
          message: error.try(:message).to_s.first(200),
          fingerprint: error.try(:fingerprint),
          occurrences_count: occurrences_count
        }
      end
    rescue StandardError
      []
    end

    def metric_window_param
      window = params[:window].to_s
      return "1h" if window == "1h"
      return "7d" if window == "7d"
      return "30d" if window == "30d"

      "24h"
    end

    def metric_dimension_param
      allowed = %w[source name deployment_id service_version environment_name entity_type]
      requested = params[:dimension].to_s
      allowed.include?(requested) ? requested : "source"
    end

    def summary_scope_for_metrics
      summary_scope_base_for_metrics.where("started_at >= ?", window_start_for_metrics)
    end

    def summary_scope_base_for_metrics
      scope = SolidEvents::Summary.all
      scope = scope.where(environment_name: params[:environment_name]) if params[:environment_name].present?
      scope = scope.where(service_name: params[:service_name]) if params[:service_name].present?
      scope = apply_feature_slice_filter_to_summaries(scope)
      scope
    end

    def apply_feature_slice_filter(scope)
      feature_key = params[:feature_key].to_s
      feature_value = params[:feature_value].to_s
      return scope if feature_key.blank? || feature_value.blank?
      return scope unless SolidEvents.feature_slice_keys.include?(feature_key)

      scope.left_outer_joins(:summary)
        .where("CAST(solid_events_summaries.payload AS TEXT) LIKE ?", "%\"#{feature_key}\":\"#{feature_value}\"%")
    end

    def apply_feature_slice_filter_to_summaries(scope)
      feature_key = params[:feature_key].to_s
      feature_value = params[:feature_value].to_s
      return scope if feature_key.blank? || feature_value.blank?
      return scope unless SolidEvents.feature_slice_keys.include?(feature_key)

      scope.where("CAST(solid_events_summaries.payload AS TEXT) LIKE ?", "%\"#{feature_key}\":\"#{feature_value}\"%")
    end

    def window_start_for_metrics
      case metric_window_param
      when "1h"
        1.hour.ago
      when "7d"
        7.days.ago
      when "30d"
        30.days.ago
      else
        24.hours.ago
      end
    end

    def metric_param
      allowed = %w[error_rate latency_avg]
      requested = params[:metric].to_s
      allowed.include?(requested) ? requested : "error_rate"
    end

    def metric_compare_windows
      current_window = normalized_window(params[:window])
      baseline_window = normalized_window(params[:baseline_window].presence || current_window)
      current_duration = duration_for_window(current_window)
      baseline_duration = duration_for_window(baseline_window)
      current_end = Time.current
      current_start = current_end - current_duration
      baseline_end = current_start
      baseline_start = baseline_end - baseline_duration

      {
        current_window: current_window,
        baseline_window: baseline_window,
        current_start: current_start,
        current_end: current_end,
        baseline_start: baseline_start,
        baseline_end: baseline_end
      }
    end

    def normalized_window(value)
      window = value.to_s
      return "1h" if window == "1h"
      return "7d" if window == "7d"
      return "30d" if window == "30d"

      "24h"
    end

    def duration_for_window(window)
      case window
      when "1h" then 1.hour
      when "7d" then 7.days
      when "30d" then 30.days
      else 24.hours
      end
    end

    def grouped_metric_stats(scope:, dimension:)
      scope.group(dimension)
        .pluck(
          dimension,
          Arel.sql("COUNT(*)"),
          Arel.sql("SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END)"),
          Arel.sql("AVG(duration_ms)")
        )
        .each_with_object({}) do |(value, total_count, error_count, avg_duration_ms), memo|
          memo[value] = {
            total_count: total_count.to_i,
            error_count: error_count.to_i,
            avg_duration_ms: avg_duration_ms.to_f.round(2)
          }
        end
    end

    def journey_key_for(summary)
      return "request:#{summary.request_id}" if summary.request_id.present?
      return "entity:#{summary.entity_type}:#{summary.entity_id}" if summary.entity_type.present? && summary.entity_id.present?

      nil
    end

    def errors_only_param?
      ActiveModel::Type::Boolean.new.cast(params[:errors_only])
    end

    def export_json?
      requested = params[:format].to_s
      requested.blank? || requested == "json"
    end

    def export_filters_payload
      params.to_unsafe_h.slice(
        "status", "kind", "severity", "error_fingerprint", "entity_type", "entity_id",
        "feature_key", "feature_value", "window", "request_id", "errors_only", "limit", "cursor", "format"
      )
    end

    def duration_slice_for(summaries)
      durations = summaries.map(&:duration_ms).compact
      return {avg: 0.0, max: 0.0, p95: 0.0, sample_count: 0} if durations.empty?

      sorted = durations.sort
      index = (0.95 * (sorted.length - 1)).ceil
      {
        avg: (durations.sum.to_f / durations.length).round(2),
        max: sorted.last.to_f.round(2),
        p95: sorted[index].to_f.round(2),
        sample_count: sorted.length
      }
    end

    def error_rate_for(summaries)
      return 0.0 if summaries.empty?

      errors = summaries.count { |summary| summary.status == "error" }
      ((errors.to_f / summaries.size) * 100.0).round(2)
    end

    def default_metric_stats
      {total_count: 0, error_count: 0, avg_duration_ms: 0.0}
    end

    def metric_value_for(metric, stats)
      if metric == "latency_avg"
        stats[:avg_duration_ms].to_f.round(2)
      else
        total = stats[:total_count].to_i
        return 0.0 if total.zero?

        ((stats[:error_count].to_f / total) * 100.0).round(2)
      end
    end

    def percent_delta(current_value, baseline_value)
      baseline = baseline_value.to_f
      return nil if baseline.zero?

      (((current_value.to_f - baseline) / baseline) * 100.0).round(2)
    end

  end
end
