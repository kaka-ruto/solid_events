# frozen_string_literal: true
require "json"
require "net/http"
require "uri"

module SolidEvents
  module Notifiers
    class SlackWebhookNotifier
      def initialize(webhook_url:, channel: nil, username: "solid_events")
        @webhook_uri = URI.parse(webhook_url)
        @channel = channel
        @username = username
      end

      def call(incident:, action:)
        message = {
          username: @username,
          channel: @channel,
          text: "[solid_events] #{action.to_s.upcase} #{incident.kind} #{incident.severity} #{incident.source} #{incident.name}"
        }.compact

        request = Net::HTTP::Post.new(@webhook_uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(message)

        http = Net::HTTP.new(@webhook_uri.host, @webhook_uri.port)
        http.use_ssl = @webhook_uri.scheme == "https"
        http.read_timeout = 2
        http.open_timeout = 2
        http.request(request)
      rescue StandardError
        nil
      end
    end
  end
end
