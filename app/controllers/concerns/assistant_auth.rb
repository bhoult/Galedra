# Bearer authentication for connected assistants (Stage 12).
module AssistantAuth
  extend ActiveSupport::Concern

  private

  def current_assistant_token
    return @current_assistant_token if defined?(@current_assistant_token)

    header = request.authorization.to_s
    plaintext = header.delete_prefix("Bearer ").strip if header.start_with?("Bearer ")
    # The path form serves /mcp/:token for connector screens that take only a URL; the
    # query form went with the write link (2026-09-19): a token in a query string leaks into logs.
    plaintext ||= request.path_parameters[:token].presence
    @presented_credential = plaintext
    # An OAuth access token (Stage 16) maps onto the person's assistant token.
    if plaintext.to_s.start_with?("gat_")
      @oauth_token = OauthToken.find_usable("access", plaintext)
      @current_assistant_token = @oauth_token&.assistant_token
    else
      @current_assistant_token = AssistantToken.find_by_token(plaintext)
    end
    @current_assistant_token ||= Assistants::Connect.for_source(request.remote_ip) if plaintext.blank? && anonymous_assistant_allowed?
    @current_assistant_token
  end

  # Controllers that record investigations may act for an anonymous caller
  # with no token at all (an anonymous assistant keyed to its address for the day).
  def anonymous_assistant_allowed? = false

  def authenticate_assistant!
    token = current_assistant_token
    if token.nil? || !token.usable?
      response.set_header("WWW-Authenticate", %(Bearer resource_metadata="#{request.base_url}/.well-known/oauth-protected-resource"))
      render json: { errors: [ { code: "TOKEN_INVALID", path: "$", detail: "send a valid assistant token as Authorization: Bearer <token>; mint one at /assistants/new or connect with OAuth" } ] }, status: :unauthorized
    end
  end

  # A galedra:read OAuth token may not write (owner decision: connectors may ask for read-only).
  def read_only_assistant? = @oauth_token&.read_only? || false

  def insufficient_scope
    response.set_header("WWW-Authenticate", 'Bearer error="insufficient_scope", scope="galedra"')
    render json: { errors: [ { code: "INSUFFICIENT_SCOPE", path: "$", detail: "this connection was granted read-only access; reconnect with the galedra scope to record" } ] }, status: :forbidden
  end

  # A credential was presented but is not valid (expired access token, revoked
  # assistant): refuse, so an OAuth client refreshes rather than falling through
  # to anonymous use.
  def presented_invalid_credential?
    @presented_credential.present? && (current_assistant_token.nil? || !current_assistant_token.usable?)
  end

  def assistant_rate_limit_key
    request.authorization.present? || request.path_parameters[:token].present? || request.query_parameters["token"].present? ? (current_assistant_token&.token_digest || request.remote_ip) : request.remote_ip
  end

  def too_many_requests
    render json: { errors: [ { code: "RATE_LIMITED", path: "$", detail: "too many requests; slow down and try again in a minute" } ] }, status: :too_many_requests
  end
end
