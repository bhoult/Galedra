# frozen_string_literal: true

module Oauth
  # GET and POST /oauth/authorize (Stage 16): the one consent page. Sign-in is
  # required; the person is sent back here afterwards.
  class AuthorizationsController < ApplicationController
    def new
      @request = Oauth::Server.authorization_request!(params)
    rescue Oauth::Server::Error => e
      render_error(e)
    end

    def create
      authorization = Oauth::Server.authorization_request!(params)
      if params[:decision] != "approve"
        return redirect_to redirect_with(authorization[:redirect_uri], error: "access_denied", state: authorization[:state]), allow_other_host: true
      end

      code = OauthAuthorizationCode.issue!(client: authorization[:client], user: Current.user, redirect_uri: authorization[:redirect_uri],
                                           code_challenge: authorization[:code_challenge], scope: authorization[:scope], resource: authorization[:resource])
      redirect_to redirect_with(authorization[:redirect_uri], code: code, state: authorization[:state]), allow_other_host: true
    rescue Oauth::Server::Error => e
      render_error(e)
    end

    private

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
