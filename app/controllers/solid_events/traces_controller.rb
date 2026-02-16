# frozen_string_literal: true
require "set"

module SolidEvents
  class TracesController < ApplicationController
    PER_PAGE_OPTIONS = [25, 50, 100].freeze

    before_action :set_trace, only: :show

    def index
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

      includes = [:events, :record_links, :error_links]
      includes << :summary if summary_table_available?

      @traces = scope
        .includes(*includes)
        .offset((@page - 1) * @per_page)
        .limit(@per_page)

      SolidEvents::IncidentEvaluator.evaluate! if SolidEvents.evaluate_incidents_on_request?
      load_slo_panel(scope)
      load_index_insights
      load_incidents
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

    def show
      @events = @trace.events.order(:occurred_at)
      @record_links = @trace.record_links
      @error_links = @trace.error_links
      @event_counts = @events.reorder(nil).group(:event_type).count
      load_correlation_pivots
      load_related_traces
    end

    private

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

      if summary_table_available?
        scoped = scope.left_outer_joins(:summary)
        scoped = scoped.where("solid_events_summaries.entity_type ILIKE ?", "%#{@entity_type}%") if @entity_type.present?
        scoped = scoped.where(solid_events_summaries: {entity_id: @entity_id.to_i}) if @entity_id.present?
        return scoped
      end

      scoped = scope.left_outer_joins(:record_links)
      scoped = scoped.where("solid_events_record_links.record_type ILIKE ?", "%#{@entity_type}%") if @entity_type.present?
      scoped = scoped.where(solid_events_record_links: {record_id: @entity_id.to_i}) if @entity_id.present?
      scoped.distinct
    end

    def apply_error_fingerprint_filter(scope)
      return scope if @error_fingerprint.blank?

      if summary_table_available?
        return scope.left_outer_joins(:summary).where(solid_events_summaries: {error_fingerprint: @error_fingerprint})
      end

      apply_context_key_filter(scope, "error_fingerprint", @error_fingerprint)
    end

    def apply_request_id_filter(scope)
      return scope if @request_id.blank?

      if summary_table_available?
        return scope.left_outer_joins(:summary).where(solid_events_summaries: {request_id: @request_id})
      end

      apply_context_key_filter(scope, "request_id", @request_id)
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

    def summary_table_available?
      @summary_table_available ||= SolidEvents::Summary.connection.data_source_exists?(SolidEvents::Summary.table_name)
    rescue StandardError
      false
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
      return unless summary_table_available?

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
      return unless summary_table_available?
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
      return unless summary_table_available?

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
    end

    def incident_table_available?
      @incident_table_available ||= SolidEvents::Incident.connection.data_source_exists?(SolidEvents::Incident.table_name)
    rescue StandardError
      false
    end
  end
end
