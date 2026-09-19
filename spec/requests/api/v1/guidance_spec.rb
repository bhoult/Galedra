# frozen_string_literal: true

require "rails_helper"

# Stage 31: the rules an assistant works by, served live. MCP hosts get the same
# text on every tool result; this endpoint is for the hosts that do not speak it.
RSpec.describe "GET /api/v1/guidance (Stage 31)", type: :request do
  it "returns every topic with the version, and needs no token" do
    get "/api/v1/guidance"
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["version"]).to eq(Guidance::VERSION)
    expect(body["purpose"]).to include("not a source of truth")
    expect(body["topics"].keys).to match_array(Guidance::TOPICS.map(&:to_s))
    expect(body["topics"]["outline"]).to include("3,000 words")
  end

  it "returns one topic when asked for it" do
    get "/api/v1/guidance", params: { topic: "work" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["topics"].keys).to eq([ "work" ])
  end

  it "refuses a topic it does not have, and says which it has" do
    get "/api/v1/guidance", params: { topic: "nonsense" }
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body["topics"]).to match_array(Guidance::TOPICS.map(&:to_s))
  end

  # The point of the endpoint: what it serves is what the MCP channel serves, so
  # a rule fixed once is fixed for every host.
  it "serves the same text the MCP channel attaches to results" do
    get "/api/v1/guidance", params: { topic: "check" }
    server = Mcp::Server.allocate.send(:guidance, "record_investigation")
    expect(response.parsed_body["topics"]["check"]).to eq(server[:text])
    expect(server[:version]).to eq(Guidance::VERSION)
  end
end
