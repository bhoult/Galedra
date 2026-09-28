require "rails_helper"

# The MCP budget is one per assistant token and is for work. On 2026-09-28 a
# worker's connector probed GET /mcp — answered 405, there is no stream — 1,051
# times beside about a thousand tool calls, and the probes spent a fifth of each
# minute's allowance: in the minutes its 429s fell, the tool calls alone were
# under the limit. The refusal also said only "slow down", and the worker stopped
# cold instead of pausing (feature request 01a0e968).
RSpec.describe "MCP rate limit", type: :request do
  include EnvHelpers

  let(:token) { Assistants::Connect.call(name: "Grok", provider: "xai").last }
  let(:headers) { { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json, text/event-stream", "Authorization" => "Bearer #{token}" } }

  def ping(id)
    post "/mcp", params: { jsonrpc: "2.0", id: id, method: "ping" }.to_json, headers: headers
  end

  it "does not spend a worker's calls on the stream probe it answers 405" do
    with_rate_limiting do
      McpController::CALLS_PER_MINUTE.times { get "/mcp", headers: headers }
      expect(response).to have_http_status(:method_not_allowed)

      McpController::CALLS_PER_MINUTE.times { |i| ping(i) }
      expect(response).to have_http_status(:ok), "every probe before them came out of the calls' budget"
    end
  end

  it "keeps a limit on the probe of its own" do
    with_rate_limiting do
      (McpController::CALLS_PER_MINUTE + 1).times { get "/mcp", headers: headers }
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  it "says when to come back, and that the budget is shared by the token's workers" do
    with_rate_limiting do
      (McpController::CALLS_PER_MINUTE + 1).times { |i| ping(i) }
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to eq("60")
      error = response.parsed_body["errors"].first
      expect(error).to include("code" => "RATE_LIMITED", "retry_after_seconds" => 60)
      expect(error["detail"]).to include("#{McpController::CALLS_PER_MINUTE} calls a minute", "shared by every worker", "Retry-After")
    end
  end
end
