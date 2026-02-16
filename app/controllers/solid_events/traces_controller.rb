# frozen_string_literal: true
require "set"

module SolidEvents
  class TracesController < ApplicationController
    PER_PAGE_OPTIONS = [25, 50, 100].freeze
    COMPARE_DIMENSIONS = %w[source name deployment_id service_version environment_name entity_type].freeze
    COMPARE_METRICS = %w[error_rate latency_avg].freeze

    before_action :set_trace, only: :show

    def index
      apply_shared_view!
      apply_saved_view!
      @query = params[:q].to_s.strip
      @status = params[:status].to_s
      @trace_type = params[:trace_type].to_s
      @source = params[:source].to_s.strip
      @context_key = params[:context_key].to_s.strip
      @context_id = params[:context_id].to_s.strip
      @entity_type = params[:entity_type].to_s.strip
      @entity_id = params[:entity_id].to_s.strip
      @error_fingerprint = params[:error_fingerprint].to_s.strip
      @request_id = params[:request_id].to_s.strip
      @feature_key = params[:feature_key].to_s.strip
      @feature_value = params[:feature_value].to_s.strip
      @min_duration_ms = params[:min_duration_ms].to_s.strip
      @window = params[:window].to_s.presence || "24h"
      @page = [params[:page].to_i, 1].max
      @per_page = sanitize_per_page(params[:per_page])

      @trace_type_options = SolidEvents::Trace.distinct.order(:trace_type).pluck(:trace_type)

      scope = SolidEvents::Trace.recent
      scope = scope.where(status: @status) if @status.in?(%w[ok error])
      scope = scope.where(trace_type: @trace_type) if @trace_type.present?
      scope = scope.where("solid_events_traces.source ILIKE ?", "%#{@source}%") if @source.present?
      scope = apply_time_window(scope)
      scope = apply_context_id_filters(scope)
      scope = apply_entity_filters(scope)
      scope = apply_error_fingerprint_filter(scope)
      scope = apply_request_id_filter(scope)
      scope = apply_feature_slice_filter(scope)
      scope = apply_min_duration_filter(scope)

      if @query.present?
        scope = scope.left_outer_joins(:record_links).where(
          "solid_events_traces.name ILIKE :q OR solid_events_traces.source ILIKE :q OR " \
          "solid_events_record_links.record_type ILIKE :q OR CAST(solid_events_record_links.record_id AS TEXT) ILIKE :q",
          q: "%#{@query}%"
        ).distinct
      end

      @total_count = scope.except(:limit, :offset, :order).count("DISTINCT solid_events_traces.id")
      @error_count = scope.where(status: "error").count("DISTINCT solid_events_traces.id")
      @page_count = (@total_count.to_f / @per_page).ceil

      @traces = scope
        .includes(:events, :record_links, :error_links, :summary)
        .offset((@page - 1) * @per_page)
        .limit(@per_page)

      SolidEvents::IncidentEvaluator.evaluate! if SolidEvents.evaluate_incidents_on_request?
      load_slo_panel(scope)
      load_index_insights
      load_compare_panel
      load_journey_panel
      load_incidents
      load_saved_views
    end

    def hot_path
      @name = params[:name].to_s
      @source = params[:source].to_s
      @window = params[:window].to_s.presence || "7d"
      scope = SolidEvents::Trace.recent.where(name: @name, source: @source)
      scope = case @window
      when "24h" then scope.where("solid_events_traces.started_at >= ?", 24.hours.ago)
      else scope.where("solid_events_traces.started_at >= ?", 7.days.ago)
      end

      @traces = scope.limit(200)
      durations = @traces.filter_map do |trace|
        next unless trace.started_at && trace.finished_at

        ((trace.finished_at - trace.started_at) * 1000.0).round(2)
      end.sort
      @latency_stats = {
        count: durations.size,
        p50_ms: percentile(durations, 0.50),
        p95_ms: percentile(durations, 0.95),
        p99_ms: percentile(durations, 0.99),
        error_rate_pct: if @traces.any?
          ((@traces.count { |trace| trace.status == "error" }.to_f / @traces.size) * 100.0).round(2)
        else
          0.0
        end
      }
      @hourly = @traces.group_by { |trace| trace.started_at&.beginning_of_hour }.sort_by { |hour, _| hour || Time.at(0) }.last(24).map do |hour, rows|
        bucket_durations = rows.filter_map do |trace|
          next unless trace.started_at && trace.finished_at

          ((trace.finished_at - trace.started_at) * 1000.0).round(2)
        end.sort
        {
          hour: hour,
          count: rows.size,
          error_count: rows.count { |trace| trace.status == "error" },
          p95_ms: percentile(bucket_durations, 0.95)
        }
      end
    end

    def timeline
      @request_id = params[:request_id].to_s.strip
      @entity_type = params[:entity_type].to_s.strip
      @entity_id = params[:entity_id].to_s.strip
      @window = params[:window].to_s.presence || "24h"
      @timeline_rows = []

      summaries = SolidEvents::Summary.where(started_at: journey_window_start..Time.current).order(started_at: :asc)
      if @request_id.present?
        summaries = summaries.where(request_id: @request_id)
      elsif @entity_type.present? && @entity_id.present?
        summaries = summaries.where(entity_type: @entity_type, entity_id: @entity_id.to_i)
      else
        summaries = summaries.none
      end

      traces = SolidEvents::Trace.includes(:events, :summary).where(id: summaries.limit(100).pluck(:trace_id)).order(started_at: :asc)
      @timeline_rows = traces.flat_map do |trace|
        base = [{
          at: trace.started_at,
          kind: "trace",
          label: "#{trace.name} (#{trace.status})",
          trace_id: trace.id,
          details: trace.source
        }]
        events = trace.events.order(:occurred_at).map do |event|
          {
            at: event.occurred_at,
            kind: event.event_type,
            label: event.name,
            trace_id: trace.id,
            details: event.duration_ms ? "#{event.duration_ms} ms" : nil
          }
        end
        base + events
      end.sort_by { |row| row[:at] || Time.at(0) }
      append_incident_lifecycle_rows!(summaries)
    end

    def show
      @events = @trace.events.order(:occurred_at)
      @record_links = @trace.record_links
      @error_links = @trace.error_links
      @event_counts = @events.reorder(nil).group(:event_type).count
      load_correlation_pivots
      load_related_traces
    end

    private

    def apply_shared_view!
      token = params[:shared_view].to_s
      return if token.blank?
      return unless request.get?

      decoded = shared_view_verifier.verified(token)
      return unless decoded.is_a?(Hash)

      filters = decoded["filters"].to_h.transform_keys(&:to_s)
      filters.each do |key, value|
        params[key] = value if params[key].blank?
      end
      @active_shared_view_label = decoded["label"].to_s.presence
    rescue StandardError
      nil
    end

    def apply_saved_view!
      saved_view = SolidEvents::SavedView.find_by(id: params[:saved_view_id])
      return unless saved_view
      return unless request.get?

      saved_filters = saved_view.filters.to_h.transform_keys(&:to_s)
      saved_filters.each do |key, value|
        params[key] = value if params[key].blank?
      end
      @active_saved_view = saved_view
    end

    def sanitize_per_page(value)
      candidate = value.to_i
      return 50 unless PER_PAGE_OPTIONS.include?(candidate)

      candidate
    end

    def apply_time_window(scope)
      case @window
      when "1h"
        scope.where("solid_events_traces.started_at >= ?", 1.hour.ago)
      when "24h"
        scope.where("solid_events_traces.started_at >= ?", 24.hours.ago)
      when "7d"
        scope.where("solid_events_traces.started_at >= ?", 7.days.ago)
      else
        scope
      end
    end

    def apply_context_id_filters(scope)
      scope = apply_context_key_filter(scope, @context_key, @context_id) if @context_key.present?
      scope
    end

    def apply_context_key_filter(scope, key, value)
      return scope if value.blank?

      escaped_value = ActiveRecord::Base.sanitize_sql_like(value)
      scope.where("CAST(solid_events_traces.context AS TEXT) LIKE ?", "%\"#{key}\":#{escaped_value}%")
    end

    def apply_entity_filters(scope)
      return scope if @entity_type.blank? && @entity_id.blank?

      scoped = scope.left_outer_joins(:summary)
      scoped = scoped.where("solid_events_summaries.entity_type ILIKE ?", "%#{@entity_type}%") if @entity_type.present?
      scoped = scoped.where(solid_events_summaries: {entity_id: @entity_id.to_i}) if @entity_id.present?
      scoped
    end

    def apply_error_fingerprint_filter(scope)
      return scope if @error_fingerprint.blank?

      scope.left_outer_joins(:summary).where(solid_events_summaries: {error_fingerprint: @error_fingerprint})
    end

    def apply_request_id_filter(scope)
      return scope if @request_id.blank?

      scope.left_outer_joins(:summary).where(solid_events_summaries: {request_id: @request_id})
    end

    def apply_feature_slice_filter(scope)
      return scope if @feature_key.blank? || @feature_value.blank?
      return scope unless SolidEvents.feature_slice_keys.include?(@feature_key)

      scope.left_outer_joins(:summary)
        .where("CAST(solid_events_summaries.payload AS TEXT) LIKE ?", "%\"#{@feature_key}\":\"#{@feature_value}\"%")
    end

    def set_trace
      @trace = SolidEvents::Trace.find(params[:id])
    end

    def apply_min_duration_filter(scope)
      return scope if @min_duration_ms.blank?

      min_duration = @min_duration_ms.to_f
      return scope if min_duration <= 0

      scope.where("solid_events_traces.finished_at IS NOT NULL")
        .where("EXTRACT(EPOCH FROM (solid_events_traces.finished_at - solid_events_traces.started_at)) * 1000 >= ?", min_duration)
    end

    def load_correlation_pivots
      @correlation = {
        entity_trace_count: 0,
        entity_error_count: 0,
        fingerprint_trace_count: 0,
        fingerprint_error_count: 0,
        recent_avg_duration_ms: nil,
        baseline_avg_duration_ms: nil,
        duration_regression: false
      }
      summaries = SolidEvents::Summary.where(started_at: 7.days.ago..Time.current)

      if @trace.summary&.entity_type.present? && @trace.summary&.entity_id.present?
        entity_scope = summaries.where(entity_type: @trace.summary.entity_type, entity_id: @trace.summary.entity_id)
        @correlation[:entity_trace_count] = entity_scope.count
        @correlation[:entity_error_count] = entity_scope.where(status: "error").count
      end

      if @trace.summary&.error_fingerprint.present?
        fingerprint_scope = summaries.where(error_fingerprint: @trace.summary.error_fingerprint)
        @correlation[:fingerprint_trace_count] = fingerprint_scope.count
        @correlation[:fingerprint_error_count] = fingerprint_scope.where(status: "error").count
      end

      source_scope = SolidEvents::Summary.where(source: @trace.source, name: @trace.name)
      recent_scope = source_scope.where(started_at: 24.hours.ago..Time.current).where.not(duration_ms: nil)
      baseline_scope = source_scope.where(started_at: 7.days.ago...24.hours.ago).where.not(duration_ms: nil)

      @correlation[:recent_avg_duration_ms] = recent_scope.average(:duration_ms)&.to_f&.round(2)
      @correlation[:baseline_avg_duration_ms] = baseline_scope.average(:duration_ms)&.to_f&.round(2)

      if @correlation[:recent_avg_duration_ms] && @correlation[:baseline_avg_duration_ms]
        @correlation[:duration_regression] =
          @correlation[:recent_avg_duration_ms] > (@correlation[:baseline_avg_duration_ms] * 1.5) &&
          (@correlation[:recent_avg_duration_ms] - @correlation[:baseline_avg_duration_ms]) >= 50
      end
    end

    def load_related_traces
      @related_entity_traces = []
      @related_fingerprint_traces = []
      return unless @trace.summary

      base_scope = SolidEvents::Trace.recent.where.not(id: @trace.id).includes(:summary)

      if @trace.summary.entity_type.present? && @trace.summary.entity_id.present?
        @related_entity_traces = base_scope
          .left_outer_joins(:summary)
          .where(solid_events_summaries: {entity_type: @trace.summary.entity_type, entity_id: @trace.summary.entity_id})
          .limit(10)
      end

      return unless @trace.summary.error_fingerprint.present?

      @related_fingerprint_traces = base_scope
        .left_outer_joins(:summary)
        .where(solid_events_summaries: {error_fingerprint: @trace.summary.error_fingerprint})
        .limit(10)
    end

    def load_index_insights
      @regression_candidates = []
      @new_error_fingerprints = []
      @hot_paths = []
      @new_error_fingerprints_since_deploy = []
      summaries = SolidEvents::Summary.where(started_at: 7.days.ago..Time.current).where.not(duration_ms: nil)
      grouped = summaries.group_by { |summary| [summary.name, summary.source] }
      @hot_paths = grouped.filter_map do |(name, source), rows|
        durations = rows.map(&:duration_ms).compact.sort
        next if durations.size < 5

        {
          name: name,
          source: source,
          link: hot_path_path(name: name, source: source),
          count: durations.size,
          p50_ms: percentile(durations, 0.50),
          p95_ms: percentile(durations, 0.95),
          p99_ms: percentile(durations, 0.99),
          error_rate_pct: ((rows.count { |row| row.status == "error" }.to_f / rows.size) * 100.0).round(2)
        }
      end.sort_by { |entry| -entry[:p95_ms] }.first(15)

      @regression_candidates = grouped.filter_map do |(name, source), rows|
        recent = rows.select { |row| row.started_at >= 24.hours.ago }.map(&:duration_ms)
        baseline = rows.select { |row| row.started_at < 24.hours.ago }.map(&:duration_ms)
        next if recent.size < 3 || baseline.size < 5

        recent_avg = (recent.sum / recent.size).round(2)
        baseline_avg = (baseline.sum / baseline.size).round(2)
        next unless recent_avg > (baseline_avg * 1.5) && (recent_avg - baseline_avg) >= 50

        {
          name: name,
          source: source,
          recent_avg_duration_ms: recent_avg,
          baseline_avg_duration_ms: baseline_avg,
          delta_ms: (recent_avg - baseline_avg).round(2)
        }
      end.sort_by { |candidate| -candidate[:delta_ms] }.first(10)

      recent_fingerprint_scope = SolidEvents::Summary
        .where(started_at: 24.hours.ago..Time.current)
        .where.not(error_fingerprint: [nil, ""])
      baseline_fingerprints = SolidEvents::Summary
        .where(started_at: 7.days.ago...24.hours.ago)
        .where.not(error_fingerprint: [nil, ""])
        .distinct
        .pluck(:error_fingerprint)
        .to_set

      @new_error_fingerprints = recent_fingerprint_scope
        .where.not(error_fingerprint: baseline_fingerprints.to_a)
        .order(started_at: :desc)
        .limit(10)
        .map { |summary| {fingerprint: summary.error_fingerprint, source: summary.source, trace_id: summary.trace_id} }
        .uniq { |entry| entry[:fingerprint] }

      @new_error_fingerprints_since_deploy = fingerprints_since_current_deploy
    rescue StandardError
      @regression_candidates = []
      @new_error_fingerprints = []
      @hot_paths = []
      @new_error_fingerprints_since_deploy = []
    end

    def load_compare_panel
      @compare_dimension = params[:compare_dimension].to_s
      @compare_dimension = "source" unless @compare_dimension.in?(COMPARE_DIMENSIONS)
      @compare_metric = params[:compare_metric].to_s
      @compare_metric = "error_rate" unless @compare_metric.in?(COMPARE_METRICS)
      @compare_window = params[:compare_window].to_s
      @compare_window = "24h" unless @compare_window.in?(%w[1h 24h 7d 30d])
      @compare_baseline_window = params[:compare_baseline_window].to_s
      @compare_baseline_window = @compare_window unless @compare_baseline_window.in?(%w[1h 24h 7d 30d])
      @compare_rows = []

      windows = compare_windows
      scope = SolidEvents::Summary.all
      current = grouped_compare_stats(scope.where(started_at: windows[:current_start]..windows[:current_end]))
      baseline = grouped_compare_stats(scope.where(started_at: windows[:baseline_start]..windows[:baseline_end]))
      keys = (current.keys + baseline.keys).uniq
      @compare_rows = keys.map do |key|
        current_stats = current.fetch(key, compare_default_stats)
        baseline_stats = baseline.fetch(key, compare_default_stats)
        current_value = compare_metric_value(current_stats)
        baseline_value = compare_metric_value(baseline_stats)
        delta = (current_value - baseline_value).round(2)
        {
          key: key,
          current: current_value,
          baseline: baseline_value,
          delta: delta,
          delta_pct: compare_delta_pct(current_value, baseline_value),
          current_count: current_stats[:count],
          baseline_count: baseline_stats[:count]
        }
      end.sort_by { |row| [-row[:current_count], row[:key].to_s] }.first(10)
    end

    def load_journey_panel
      @journey_group_by = params[:journey_group_by].to_s
      @journey_group_by = "request" unless @journey_group_by.in?(%w[request entity])
      @journey_errors_only = ActiveModel::Type::Boolean.new.cast(params[:journey_errors_only])
      @journey_limit = [[params[:journey_limit].to_i, 1].max, 20].min
      @journey_limit = 5 if params[:journey_limit].blank?
      @journey_rows = []

      summaries = SolidEvents::Summary.where(started_at: journey_window_start..Time.current)
      summaries = summaries.where.not(request_id: [nil, ""]) if @journey_group_by == "request"
      summaries = summaries.where.not(entity_type: [nil, ""]).where.not(entity_id: nil) if @journey_group_by == "entity"
      summaries = summaries.where(status: "error") if @journey_errors_only
      summaries = summaries.order(started_at: :desc).limit(1_500)

      grouped = summaries.group_by do |summary|
        if @journey_group_by == "request"
          "request:#{summary.request_id}"
        else
          "entity:#{summary.entity_type}:#{summary.entity_id}"
        end
      end

      @journey_rows = grouped.map do |journey_key, rows|
        ordered = rows.sort_by(&:started_at)
        last = ordered.last
        {
          journey_key: journey_key,
          request_id: last.request_id,
          entity_type: last.entity_type,
          entity_id: last.entity_id,
          trace_count: rows.size,
          error_count: rows.count { |row| row.status == "error" },
          started_at: ordered.first.started_at,
          finished_at: last.finished_at || last.started_at
        }
      end.sort_by { |row| row[:finished_at] || Time.at(0) }.reverse.first(@journey_limit)
    end

    def journey_window_start
      case @window
      when "1h" then 1.hour.ago
      when "7d" then 7.days.ago
      else 24.hours.ago
      end
    end

    def compare_windows
      current_duration = compare_window_duration(@compare_window)
      baseline_duration = compare_window_duration(@compare_baseline_window)
      current_end = Time.current
      current_start = current_end - current_duration
      baseline_end = current_start
      baseline_start = baseline_end - baseline_duration
      {
        current_start: current_start,
        current_end: current_end,
        baseline_start: baseline_start,
        baseline_end: baseline_end
      }
    end

    def compare_window_duration(window)
      case window
      when "1h" then 1.hour
      when "7d" then 7.days
      when "30d" then 30.days
      else 24.hours
      end
    end

    def grouped_compare_stats(scope)
      scope.group(@compare_dimension)
        .pluck(
          @compare_dimension,
          Arel.sql("COUNT(*)"),
          Arel.sql("SUM(CASE WHEN status = 'error' THEN 1 ELSE 0 END)"),
          Arel.sql("AVG(duration_ms)")
        ).each_with_object({}) do |(key, count, error_count, avg_duration), memo|
          memo[key] = {
            count: count.to_i,
            error_count: error_count.to_i,
            avg_duration: avg_duration.to_f.round(2)
          }
        end
    end

    def compare_metric_value(stats)
      if @compare_metric == "latency_avg"
        stats[:avg_duration].to_f.round(2)
      else
        return 0.0 if stats[:count].to_i.zero?

        ((stats[:error_count].to_f / stats[:count]) * 100.0).round(2)
      end
    end

    def compare_delta_pct(current_value, baseline_value)
      baseline = baseline_value.to_f
      return nil if baseline.zero?

      (((current_value.to_f - baseline) / baseline) * 100.0).round(2)
    end

    def compare_default_stats
      {count: 0, error_count: 0, avg_duration: 0.0}
    end

    def percentile(sorted_values, ratio)
      return nil if sorted_values.empty?

      index = (ratio * (sorted_values.length - 1)).ceil
      sorted_values[index].to_f.round(2)
    end

    def fingerprints_since_current_deploy
      deploy_id = SolidEvents.deployment_id.to_s
      version = SolidEvents.service_version.to_s
      return [] if deploy_id.blank? && version.blank?

      current_scope = SolidEvents::Summary.where.not(error_fingerprint: [nil, ""])
      current_scope = current_scope.where(deployment_id: deploy_id) if deploy_id.present?
      current_scope = current_scope.where(service_version: version) if version.present?
      current_scope = current_scope.where(started_at: 7.days.ago..Time.current)

      baseline_scope = SolidEvents::Summary.where.not(error_fingerprint: [nil, ""])
      baseline_scope = baseline_scope.where.not(deployment_id: deploy_id) if deploy_id.present?
      baseline_scope = baseline_scope.where.not(service_version: version) if version.present?
      baseline_scope = baseline_scope.where(started_at: 14.days.ago...7.days.ago)

      baseline = baseline_scope.distinct.pluck(:error_fingerprint).to_set

      current_scope
        .where.not(error_fingerprint: baseline.to_a)
        .order(started_at: :desc)
        .limit(15)
        .map { |summary| {fingerprint: summary.error_fingerprint, source: summary.source, trace_id: summary.trace_id} }
        .uniq { |entry| entry[:fingerprint] }
    end

    def load_slo_panel(scope)
      traces = scope.limit(500)
      durations = traces.filter_map do |trace|
        next unless trace.started_at && trace.finished_at

        ((trace.finished_at - trace.started_at) * 1000.0).round(2)
      end.sort

      @slo_panel = {
        throughput: traces.size,
        error_rate_pct: if traces.any?
          ((traces.count { |trace| trace.status == "error" }.to_f / traces.size) * 100.0).round(2)
        else
          0.0
        end,
        p95_ms: percentile(durations, 0.95),
        p99_ms: percentile(durations, 0.99)
      }
    end

    def load_incidents
      @incidents = if incident_table_available?
        SolidEvents::Incident.active_first.limit(25)
      else
        []
      end
      @incident_journey_links = @incidents.each_with_object({}) do |incident, memo|
        memo[incident.id] = build_incident_journey_link(incident)
      end
    end

    def load_saved_views
      @saved_views = if saved_views_table_available?
        SolidEvents::SavedView.recent.limit(20)
      else
        []
      end
      @saved_view_share_links = @saved_views.each_with_object({}) do |saved_view, memo|
        memo[saved_view.id] = traces_path(shared_view: shared_view_verifier.generate(shared_view_payload(saved_view)))
      end
    end

    def incident_table_available?
      @incident_table_available ||= SolidEvents::Incident.connection.data_source_exists?(SolidEvents::Incident.table_name)
    rescue StandardError
      false
    end

    def saved_views_table_available?
      @saved_views_table_available ||= SolidEvents::SavedView.connection.data_source_exists?(SolidEvents::SavedView.table_name)
    rescue StandardError
      false
    end

    def shared_view_payload(saved_view)
      {
        "label" => saved_view.name.to_s,
        "filters" => saved_view.filters.to_h,
        "generated_at" => Time.current.iso8601
      }
    end

    def shared_view_verifier
      @shared_view_verifier ||= ActiveSupport::MessageVerifier.new(
        Rails.application.secret_key_base,
        digest: "SHA256",
        serializer: JSON
      )
    end

    def build_incident_journey_link(incident)
      query = incident.payload.to_h["trace_query"].to_h
      summary = summary_for_incident_query(query: query, incident: incident)

      if query["request_id"].present? || summary&.request_id.present?
        request_id = query["request_id"].presence || summary.request_id
        return {
          ui_path: traces_path(request_id: request_id, journey_group_by: "request"),
          api_path: "/solid_events/api/journeys?request_id=#{CGI.escape(request_id)}&window=#{@window}"
        }
      end

      entity_type = query["entity_type"].presence || summary&.entity_type
      entity_id = query["entity_id"].presence || summary&.entity_id
      return if entity_type.blank? || entity_id.blank?

      {
        ui_path: traces_path(entity_type: entity_type, entity_id: entity_id, journey_group_by: "entity"),
        api_path: "/solid_events/api/journeys?entity_type=#{CGI.escape(entity_type)}&entity_id=#{entity_id}&window=#{@window}"
      }
    end

    def summary_for_incident_query(query:, incident:)
      summaries = SolidEvents::Summary.order(started_at: :desc)
      if query["name"].present?
        summaries = summaries.where(name: query["name"])
      else
        summaries = summaries.where(name: incident.name) if incident.name.present?
      end
      if query["source"].present?
        summaries = summaries.where(source: query["source"])
      else
        summaries = summaries.where(source: incident.source) if incident.source.present?
      end
      summaries = summaries.where(error_fingerprint: query["error_fingerprint"]) if query["error_fingerprint"].present?
      summaries.first
    rescue StandardError
      nil
    end

    def append_incident_lifecycle_rows!(summaries)
      pairs = summaries.map { |summary| [summary.name, summary.source] }.uniq
      incidents = pairs.flat_map do |name, source|
        SolidEvents::Incident.where(name: name, source: source).limit(20).to_a
      end.uniq(&:id)
      incident_rows = incidents.flat_map { |incident| lifecycle_rows_for(incident) }
      @timeline_rows = (@timeline_rows + incident_rows).sort_by { |row| row[:at] || Time.at(0) }
    rescue StandardError
      @timeline_rows ||= []
    end

    def lifecycle_rows_for(incident)
      events = incident.incident_events.order(:occurred_at)
      return [] if events.empty?

      events.map do |event|
        {
          at: event.occurred_at,
          kind: "incident",
          label: "incident #{event.action}: #{incident.kind}",
          trace_id: nil,
          details: "status=#{incident.status} severity=#{incident.severity} id=#{incident.id} actor=#{event.actor.presence || 'system'}"
        }
      end
    end
  end
end
