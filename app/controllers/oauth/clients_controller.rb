# frozen_string_literal: true

module Oauth
  # POST /oauth/register: dynamic client registration (RFC 7591).
  class ClientsController < ActionController::API
    rate_limit to: 20, within: 1.hour, by: -> { request.remote_ip }, with: -> { render json: { error: "rate_limited" }, status: :too_many_requests }, store: Assistants::RateLimitStore

    def create
      body = JSON.parse(request.raw_post.presence || "{}")
      render json: Oauth::Server.register(body), status: :created
    rescue JSON::ParserError
      render json: { error: "invalid_client_metadata", error_description: "body is not valid JSON" }, status: :bad_request
    rescue Oauth::Server::Error => e
      render json: e.to_h, status: e.status
    end
  end
end
