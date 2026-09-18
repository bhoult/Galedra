# POST /mcp (Stage 14): Model Context Protocol over streamable HTTP, one
# JSON-RPC message per request, JSON responses. GET is not served: the
# server pushes nothing.
class McpController < ActionController::API
  include AssistantAuth

  rate_limit to: 120, within: 1.minute, by: -> { assistant_rate_limit_key }, with: -> { too_many_requests }, store: Assistants::RateLimitStore

  def create
    return unauthorized if auth_required? && (current_assistant_token.nil? || !current_assistant_token.usable?)
    return unauthorized if presented_invalid_credential?

    message = JSON.parse(request.raw_post.presence || "")
    status, body = Mcp::Server.new(token: current_assistant_token, base_url: request.base_url, read_only: read_only_assistant?).handle(message)
    response.set_header("MCP-Protocol-Version", Mcp::Server::PROTOCOL_VERSION)
    body.nil? ? head(status) : render(json: body, status: status)
  rescue JSON::ParserError => e
    render json: { jsonrpc: "2.0", id: nil, error: { code: Mcp::Server::PARSE_ERROR, message: "body is not valid JSON: #{e.message}" } }, status: :bad_request
  end

  def show
    head :method_not_allowed
  end

  private

  # Path defaults, read without touching the request body (which may not be JSON yet).
  def auth_required? = request.path_parameters[:require_auth].present?

  def anonymous_assistant_allowed? = !auth_required?

  # The OAuth discovery hook (MCP authorization, RFC 9728): a 401 naming the
  # protected resource metadata, which names the authorization server.
  def unauthorized
    resource = auth_required? ? "#{request.base_url}/.well-known/oauth-protected-resource/mcp/connect" : "#{request.base_url}/.well-known/oauth-protected-resource/mcp"
    response.set_header("WWW-Authenticate", %(Bearer resource_metadata="#{resource}", scope="galedra"))
    render json: { jsonrpc: "2.0", id: nil, error: { code: Mcp::Server::TOKEN_REQUIRED, message: "authentication required: complete OAuth at #{request.base_url}/.well-known/oauth-authorization-server" } }, status: :unauthorized
  end
end
