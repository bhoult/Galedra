# POST /mcp (Stage 14): Model Context Protocol over streamable HTTP, one
# JSON-RPC message per request, JSON responses. GET is not served: the
# server pushes nothing, and 405 is also what revision 2026-07-28 requires of
# a server that does not host the removed GET stream.
#
# Stage 32: both eras are served here. Mcp::Era reads the request and decides
# which, so a modern client gets modern shapes and every connector already
# talking to this endpoint keeps the behaviour it has.
class McpController < ActionController::API
  include AssistantAuth

  # The budget is for work, one per assistant token, shared by every worker
  # using it. It was also being spent by the GET this server answers 405: one
  # worker's connector sent 1,051 of those beside about a thousand tool calls on
  # 2026-09-28, a fifth of each minute's allowance, and in the minutes its 429s
  # fell the tool calls alone were under the limit (feature request 01a0e968).
  # The probe keeps a limit of its own, so neither kind of request is unbounded.
  CALLS_PER_MINUTE = 120
  rate_limit to: CALLS_PER_MINUTE, within: 1.minute, by: -> { assistant_rate_limit_key }, with: -> { too_many_requests }, store: Assistants::RateLimitStore, only: :create
  rate_limit to: CALLS_PER_MINUTE, within: 1.minute, by: -> { assistant_rate_limit_key }, with: -> { too_many_requests }, store: Assistants::RateLimitStore, only: :show, name: "probe"

  def create
    return unauthorized if auth_required? && (current_assistant_token.nil? || !current_assistant_token.usable?)
    return unauthorized if presented_invalid_credential?

    message = JSON.parse(request.raw_post.presence || "")
    Rails.logger.info("mcp #{message['method'] if message.is_a?(Hash)} #{message.dig('params', 'name') if message.is_a?(Hash)} ua=#{request.user_agent.to_s[0, 40].inspect} token=#{current_assistant_token ? (current_assistant_token.anonymous? ? 'anonymous' : 'named') : 'none'}")
    era = Mcp::Era.new(message: message, protocol_version: request.headers["MCP-Protocol-Version"],
                       mcp_method: request.headers["Mcp-Method"], mcp_name: request.headers["Mcp-Name"])
    status, body = Mcp::Server.new(token: current_assistant_token, base_url: request.base_url, read_only: read_only_assistant?).handle(message, era: era)
    response.set_header("MCP-Protocol-Version", era.modern? ? era.version : Mcp::Server::PROTOCOL_VERSION)
    body.nil? ? head(status) : render(json: body, status: status)
  rescue JSON::ParserError => e
    render json: { jsonrpc: "2.0", id: nil, error: { code: Mcp::Server::PARSE_ERROR, message: "body is not valid JSON: #{e.message}" } }, status: :bad_request
  end

  def show
    head :method_not_allowed
  end

  private

  # When, not only that. A worker told "slow down and try again in a minute"
  # stopped cold mid-batch rather than pausing (01a0e968). The window is fixed
  # and at most a minute long, so sixty seconds is an honest upper bound.
  def too_many_requests
    response.set_header("Retry-After", "60")
    render json: { errors: [ { code: "RATE_LIMITED", path: "$", retry_after_seconds: 60,
                               detail: "at most #{CALLS_PER_MINUTE} calls a minute for one assistant token, shared by every worker using it, " \
                                       "and this minute's are spent. Wait up to 60 seconds (Retry-After) and carry on where you were: " \
                                       "a lease you hold stays yours until it expires." } ] }, status: :too_many_requests
  end

  # Path defaults, read without touching the request body (which may not be JSON yet).
  def auth_required? = request.path_parameters[:require_auth].present?

  def anonymous_assistant_allowed? = !auth_required?

  # The OAuth discovery hook (MCP authorization, RFC 9728): a 401 naming the
  # protected resource metadata, which names the authorization server.
  def unauthorized
    resource = auth_required? ? "#{request.base_url}/.well-known/oauth-protected-resource/mcp/connect" : "#{request.base_url}/.well-known/oauth-protected-resource/mcp"
    response.set_header("WWW-Authenticate", %(Bearer resource_metadata="#{resource}", scope="galedra"))
    render json: { jsonrpc: "2.0", id: nil, error: { code: Mcp::Server::TOKEN_REQUIRED, message: "authentication required: this call carried a token that is not usable, or none where one is required. #{Mcp::Server.ways_in(request.base_url)} OAuth metadata: #{request.base_url}/.well-known/oauth-authorization-server" } }, status: :unauthorized
  end
end
