# frozen_string_literal: true

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
        .includes(:events, :record_links, :error_links)
        .offset((@page - 1) * @per_page)
        .limit(@per_page)
    end

    def show
      @events = @trace.events.order(:occurred_at)
      @record_links = @trace.record_links
      @error_links = @trace.error_links
      @event_counts = @events.reorder(nil).group(:event_type).count
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
  end
end
