# POST /mcp (Stage 14): Model Context Protocol over streamable HTTP, one
# JSON-RPC message per request, JSON responses. GET is not served: the
# server pushes nothing.
class McpController < ActionController::API
  include AssistantAuth

  rate_limit to: 120, within: 1.minute, by: -> { assistant_rate_limit_key }, with: -> { too_many_requests }, store: Assistants::RateLimitStore

  def create
    message = JSON.parse(request.raw_post.presence || "")
    status, body = Mcp::Server.new(token: current_assistant_token, base_url: request.base_url).handle(message)
    response.set_header("MCP-Protocol-Version", Mcp::Server::PROTOCOL_VERSION)
    body.nil? ? head(status) : render(json: body, status: status)
  rescue JSON::ParserError => e
    render json: { jsonrpc: "2.0", id: nil, error: { code: Mcp::Server::PARSE_ERROR, message: "body is not valid JSON: #{e.message}" } }, status: :bad_request
  end

  def show
    head :method_not_allowed
  end
end
