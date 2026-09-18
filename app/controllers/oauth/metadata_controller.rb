# frozen_string_literal: true

module Oauth
  # RFC 8414 and RFC 9728 discovery documents (Stage 16).
  class MetadataController < ActionController::API
    def authorization_server
      render json: Oauth::Server.authorization_server_metadata(request.base_url)
    end

    # No ID tokens are issued; an empty key set keeps OpenID discovery parsers content.
    def jwks
      render json: { keys: [] }
    end

    def protected_resource
      path = request.path.end_with?("/mcp") ? "/mcp" : "/mcp/connect"
      render json: Oauth::Server.protected_resource_metadata(request.base_url, path: path)
    end
  end
end
