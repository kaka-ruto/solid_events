# frozen_string_literal: true

module SolidEvents
  class SavedViewsController < ApplicationController
    def create
      SolidEvents::SavedView.create!(
        name: params[:name].to_s.strip,
        filters: filters_payload,
        created_by: params[:created_by].to_s.presence
      )
      redirect_to traces_path, notice: "Saved view created."
    rescue StandardError => e
      redirect_to traces_path, alert: "Could not save view: #{e.message}"
    end

    def destroy
      saved_view = SolidEvents::SavedView.find(params[:id])
      saved_view.destroy!
      redirect_to traces_path, notice: "Saved view removed."
    rescue StandardError => e
      redirect_to traces_path, alert: "Could not remove view: #{e.message}"
    end

    private

    def filters_payload
      raw = params[:filters]
      return {} unless raw.respond_to?(:to_unsafe_h) || raw.respond_to?(:to_h)

      data = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      data.to_h.transform_keys(&:to_s).slice(*allowed_filter_keys)
    end

    def allowed_filter_keys
      %w[
        q status trace_type source context_key context_id entity_type entity_id
        error_fingerprint request_id feature_key feature_value window min_duration_ms
        compare_dimension compare_metric compare_window compare_baseline_window
        journey_group_by journey_limit
      ]
    end
  end
end
