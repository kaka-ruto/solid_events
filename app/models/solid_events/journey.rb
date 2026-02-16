# frozen_string_literal: true

module SolidEvents
  class Journey < Record
    self.table_name = "solid_events_journeys"

    validates :journey_key, :started_at, :finished_at, presence: true

    class << self
      def materialize_from_summary!(summary)
        key = journey_key_for(summary)
        return if key.blank?

        journey = find_or_initialize_by(journey_key: key)
        journey.request_id = summary.request_id if summary.request_id.present?
        journey.entity_type = summary.entity_type if summary.entity_type.present?
        journey.entity_id = summary.entity_id if summary.entity_id.present?
        journey.last_trace_id = summary.trace_id
        journey.started_at = [journey.started_at, summary.started_at].compact.min || summary.started_at
        journey.finished_at = [journey.finished_at, summary.finished_at || summary.started_at].compact.max || summary.started_at
        journey.trace_count = summary_count_for(key)
        journey.error_count = summary_error_count_for(key)
        journey.payload = {
          source: summary.source,
          name: summary.name
        }
        journey.save!
        journey
      rescue StandardError
        nil
      end

      private

      def journey_key_for(summary)
        return "request:#{summary.request_id}" if summary.request_id.present?
        return "entity:#{summary.entity_type}:#{summary.entity_id}" if summary.entity_type.present? && summary.entity_id.present?

        nil
      end

      def summary_scope_for_key(key)
        kind, a, b = key.split(":", 3)
        if kind == "request"
          SolidEvents::Summary.where(request_id: a)
        elsif kind == "entity"
          SolidEvents::Summary.where(entity_type: a, entity_id: b.to_i)
        else
          SolidEvents::Summary.none
        end
      end

      def summary_count_for(key)
        summary_scope_for_key(key).count
      end

      def summary_error_count_for(key)
        summary_scope_for_key(key).where(status: "error").count
      end
    end
  end
end
