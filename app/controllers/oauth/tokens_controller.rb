# frozen_string_literal: true

module Oauth
  # POST /oauth/token and POST /oauth/revoke (Stage 16).
  class TokensController < ActionController::API
    rate_limit to: 60, within: 1.minute, by: -> { request.remote_ip }, with: -> { render json: { error: "rate_limited" }, status: :too_many_requests }, store: Assistants::RateLimitStore

    def create
      Rails.logger.info("oauth token request: grant=#{params[:grant_type]} ua=#{request.user_agent.to_s[0, 60].inspect} origin=#{request.headers['Origin'].inspect} content_type=#{request.media_type.inspect}")
      client = Oauth::Server.authenticate_client!(params, request.authorization)
      response.set_header("Cache-Control", "no-store")
      case params[:grant_type].to_s
      when "authorization_code" then render json: Oauth::Server.exchange_code(client, params)
      when "refresh_token" then render json: Oauth::Server.refresh(client, params)
      else render json: { error: "unsupported_grant_type", error_description: "authorization_code or refresh_token" }, status: :bad_request
      end
    rescue Oauth::Server::Error => e
      response.set_header("WWW-Authenticate", 'Basic realm="galedra"') if e.status == 401
      render json: e.to_h, status: e.status
    end

    def revoke
      client = Oauth::Server.authenticate_client!(params, request.authorization)
      Oauth::Server.revoke(client, params)
      head :ok
    rescue Oauth::Server::Error => e
      render json: e.to_h, status: e.status
    end
  end
end
