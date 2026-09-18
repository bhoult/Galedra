# frozen_string_literal: true

module Oauth
  # GET and POST /oauth/authorize (Stage 16): the one consent page. The person
  # decides here whether to connect under their name (sign in first; they are
  # sent back) or to continue anonymously (owner decision: the choice is
  # theirs, and one plugin serves both).
  class AuthorizationsController < ApplicationController
    allow_unauthenticated_access

    def new
      @request = Oauth::Server.authorization_request!(params)
    rescue Oauth::Server::Error => e
      render_error(e)
    end

    def create
      authorization = Oauth::Server.authorization_request!(params)
      Rails.logger.info("oauth consent: decision=#{params[:decision]} client=#{authorization[:client].client_id} referer=#{request.referer.inspect} ua=#{request.user_agent.to_s[0, 60].inspect}")
      case params[:decision]
      when "approve"
        return request_authentication unless authenticated?

        code = issue(authorization, user: Current.user)
      when "anonymous"
        code = issue(authorization, user: nil, anonymous: true)
      else
        return redirect_to redirect_with(authorization[:redirect_uri], error: "access_denied", state: authorization[:state], iss: request.base_url), allow_other_host: true
      end
      # RFC 9207: iss on every authorization response, exactly the metadata issuer.
      redirect_to redirect_with(authorization[:redirect_uri], code: code, state: authorization[:state], iss: request.base_url), allow_other_host: true
    rescue Oauth::Server::Error => e
      render_error(e)
    end

    private

    def issue(authorization, user:, anonymous: false)
      OauthAuthorizationCode.issue!(client: authorization[:client], user: user, anonymous: anonymous, redirect_uri: authorization[:redirect_uri],
                                    code_challenge: authorization[:code_challenge], scope: authorization[:scope], resource: authorization[:resource])
    end

    # Sign in, then come back to this same authorization request.
    def request_authentication
      session[:return_to_after_authenticating] = oauth_authorize_url(params.permit(:client_id, :redirect_uri, :response_type, :code_challenge, :code_challenge_method, :scope, :state, :resource).to_h)
      redirect_to new_session_path
    end

    def redirect_with(uri, **query)
      parsed = URI.parse(uri)
      existing = URI.decode_www_form(parsed.query.to_s)
      parsed.query = URI.encode_www_form(existing + query.reject { |_, v| v.blank? }.to_a)
      parsed.to_s
    end

    # Errors that must not be redirected (unknown client, bad redirect URI) are shown here.
    def render_error(error)
      @error = error
      render :error, status: :bad_request
    end
  end
end
