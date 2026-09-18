# frozen_string_literal: true

module Oauth
  # Galedra as the OAuth 2.1 authorization server for its own MCP endpoint
  # (Stage 16). Metadata documents, client registration, code issuance, and
  # token exchange live here; the controllers are thin.
  module Server
    SCOPES = %w[galedra galedra:read].freeze
    DEFAULT_SCOPE = "galedra"

    class Error < StandardError
      attr_reader :code, :status

      def initialize(code, description, status: 400)
        super(description)
        @code = code
        @status = status
      end

      def to_h = { error: code, error_description: message }
    end

    module_function

    def authorization_server_metadata(base_url)
      {
        issuer: base_url,
        authorization_endpoint: "#{base_url}/oauth/authorize",
        token_endpoint: "#{base_url}/oauth/token",
        registration_endpoint: "#{base_url}/oauth/register",
        revocation_endpoint: "#{base_url}/oauth/revoke",
        scopes_supported: SCOPES,
        response_types_supported: [ "code" ],
        grant_types_supported: %w[authorization_code refresh_token],
        code_challenge_methods_supported: [ "S256" ],
        token_endpoint_auth_methods_supported: OauthClient::AUTH_METHODS,
        revocation_endpoint_auth_methods_supported: OauthClient::AUTH_METHODS,
        service_documentation: "#{base_url}/faq"
      }
    end

    def protected_resource_metadata(base_url, path: "/mcp/connect")
      { resource: "#{base_url}#{path}", authorization_servers: [ base_url ], scopes_supported: SCOPES,
        bearer_methods_supported: [ "header" ], resource_name: "Galedra MCP" }
    end

    # RFC 7591. Public clients get no secret; confidential ones get one, shown once.
    def register(params)
      redirect_uris = Array(params["redirect_uris"]).map(&:to_s)
      method = params.fetch("token_endpoint_auth_method", "none").to_s
      raise Error.new("invalid_client_metadata", "token_endpoint_auth_method must be one of #{OauthClient::AUTH_METHODS.join(', ')}") unless OauthClient::AUTH_METHODS.include?(method)
      grant_types = Array(params.fetch("grant_types", %w[authorization_code refresh_token])).map(&:to_s)
      raise Error.new("invalid_client_metadata", "only authorization_code and refresh_token grants are supported") unless (grant_types - %w[authorization_code refresh_token]).empty?

      secret = method == "none" ? nil : "gcs_#{SecureRandom.urlsafe_base64(32)}"
      client = OauthClient.new(id: SecureRandom.uuid_v7, client_id: "gci_#{SecureRandom.urlsafe_base64(16)}", name: params["client_name"].presence || "Connector",
                               redirect_uris: redirect_uris, token_endpoint_auth_method: method, client_secret_digest: secret && OauthClient.digest(secret),
                               metadata: params.slice("client_uri", "logo_uri", "software_id", "software_version", "scope").to_h)
      raise Error.new("invalid_redirect_uri", client.errors.full_messages.join("; ")) unless client.save

      response = { client_id: client.client_id, client_name: client.name, redirect_uris: client.redirect_uris, token_endpoint_auth_method: method,
                   grant_types: grant_types, response_types: [ "code" ], client_id_issued_at: client.created_at.to_i }
      response[:client_secret] = secret if secret
      response
    end

    # Validates an authorization request before the consent page is shown.
    def authorization_request!(params)
      client = OauthClient.find_by(client_id: params[:client_id].to_s)
      raise Error.new("invalid_client", "unknown client_id") if client.nil?
      raise Error.new("invalid_request", "redirect_uri is not registered for this client") unless client.redirect_uri_allowed?(params[:redirect_uri])
      raise Error.new("unsupported_response_type", "response_type must be code") unless params[:response_type].to_s == "code"
      raise Error.new("invalid_request", "code_challenge_method must be S256") unless params[:code_challenge_method].to_s == "S256"
      raise Error.new("invalid_request", "code_challenge is required") if params[:code_challenge].blank?
      scope = params[:scope].presence || DEFAULT_SCOPE
      raise Error.new("invalid_scope", "scopes supported: #{SCOPES.join(', ')}") unless (scope.split - SCOPES).empty?

      { client: client, redirect_uri: params[:redirect_uri].to_s, code_challenge: params[:code_challenge].to_s, scope: scope, state: params[:state].to_s, resource: params[:resource].presence }
    end

    def authenticate_client!(params, authorization_header)
      client_id, secret = client_credentials(params, authorization_header)
      client = OauthClient.find_by(client_id: client_id.to_s)
      raise Error.new("invalid_client", "unknown client", status: 401) if client.nil?
      raise Error.new("invalid_client", "client secret does not match", status: 401) unless client.public? || client.secret_matches?(secret)

      client
    end

    def client_credentials(params, header)
      if header.to_s.start_with?("Basic ")
        decoded = Base64.decode64(header.delete_prefix("Basic ")) rescue ""
        id, secret = decoded.split(":", 2)
        [ CGI.unescape(id.to_s), CGI.unescape(secret.to_s) ]
      else
        [ params[:client_id], params[:client_secret] ]
      end
    end

    def exchange_code(client, params)
      code = OauthAuthorizationCode.find_by(code_digest: OauthAuthorizationCode.digest(params[:code]))
      raise Error.new("invalid_grant", "unknown code") if code.nil? || code.oauth_client_id != client.id
      raise Error.new("invalid_grant", "code is expired or already used") unless code.usable?
      raise Error.new("invalid_grant", "redirect_uri does not match") unless code.redirect_uri == params[:redirect_uri].to_s
      raise Error.new("invalid_grant", "PKCE verification failed") unless code.verifier_matches?(params[:code_verifier])

      code.update!(used_at: Time.current)
      assistant = assistant_for(code.user, client)
      access, refresh = OauthToken.issue_pair!(client: client, assistant_token: assistant, scope: code.scope)
      token_response(access, refresh, code.scope)
    end

    def refresh(client, params)
      token = OauthToken.find_by(kind: "refresh", token_digest: OauthToken.digest(params[:refresh_token]))
      raise Error.new("invalid_grant", "unknown refresh token") if token.nil? || token.oauth_client_id != client.id
      if token.used_at.present? || token.revoked_at.present?
        token.revoke_family!
        raise Error.new("invalid_grant", "refresh token was already used; every token in its family is now revoked")
      end
      raise Error.new("invalid_grant", "refresh token expired or its delegation was revoked") unless token.usable?

      token.update!(used_at: Time.current)
      OauthToken.where(family_id: token.family_id, kind: "access", revoked_at: nil).update_all(revoked_at: Time.current)
      access, refresh = OauthToken.issue_pair!(client: client, assistant_token: token.assistant_token, scope: token.scope, family_id: token.family_id)
      token_response(access, refresh, token.scope)
    end

    def revoke(client, params)
      %w[access refresh].each do |kind|
        token = OauthToken.find_by(kind: kind, token_digest: OauthToken.digest(params[:token]))
        next if token.nil? || token.oauth_client_id != client.id

        token.revoke_family!
      end
      true
    end

    # One durable delegation per person per client, reused across grants.
    def assistant_for(user, client)
      existing = AssistantToken.where(user: user).where("software->>'oauth_client_id' = ?", client.client_id).order(created_at: :desc).find(&:usable?)
      return existing if existing

      record, = Assistants::Connect.call(user: user, name: client.name, provider: client.provider, model: "oauth")
      record.update!(software: record.software.merge("oauth_client_id" => client.client_id))
      record
    end

    def token_response(access, refresh, scope)
      { access_token: access, token_type: "Bearer", refresh_token: refresh, scope: scope }.tap { |r| r[:expires_in] = OauthToken::ACCESS_LIFETIME.to_i if OauthToken::ACCESS_LIFETIME }
    end
  end
end
