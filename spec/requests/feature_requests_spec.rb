require "rails_helper"

RSpec.describe "Feature requests from assistants (after Stage 19)", type: :request do
  before { release_models }

  let(:password) { "correct horse battery staple" }
  let(:user) { User.create!(email_address: "me@example.com", password: password) }
  let(:token) { Assistants::Connect.call(user: user, name: "Claude", provider: "anthropic").last }

  def rpc(method, params, tok = token)
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["Authorization"] = "Bearer #{tok}" if tok
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json, headers: headers
    response.parsed_body
  end

  def call_tool(name, arguments, tok = token)
    body = rpc("tools/call", { name: name, arguments: arguments }, tok)
    [ body.dig("result", "structuredContent"), body.dig("result", "isError"), body ]
  end

  it "records what an assistant could not do, counts repeats, caps the day, and tells the assistant it can" do
    data, err = call_tool("request_feature", { asked: "Find every claim that cites the same source", needed: "A way to list claims by source", expected: "search_claims source_id", context_tool: "get_claim" })
    expect(err).to be(false), data.inspect
    expect(data).to include("recorded" => true, "repeat" => false)
    expect(data["note"]).to include("tell the person plainly")
    data, = call_tool("request_feature", { asked: "Same again", needed: "a way to LIST claims by source!" })
    expect(data["repeat"]).to be(true)
    expect(FeatureRequest.count).to eq(1)
    expect(FeatureRequest.first).to have_attributes(count: 2, anonymous: false, expected: "search_claims source_id", context_tool: "get_claim")

    9.times { |i| call_tool("request_feature", { asked: "x", needed: "need #{i}" }) }
    data, err = call_tool("request_feature", { asked: "x", needed: "one too many" })
    expect(err).to be(true)
    expect(data["errors"].first["code"]).to eq("RATE_LIMITED")
    expect(data["hint"]).to include("request_feature")

    # Awareness: the tool is listed, every guidance block says so, and every refusal hints at it.
    tools = rpc("tools/list", {}).dig("result", "tools").map { |t| t["name"] }
    expect(tools).to include("request_feature")
    init = rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "spec", version: "0" } })
    expect(init.dig("result", "instructions")).to include("request_feature")
    data, = call_tool("search_claims", { query: "anything" })
    expect(data.dig("guidance", "text")).to include("request_feature")
    expect(data["caller"]).to include("attribution" => "named")
    data, = call_tool("search_claims", { query: "anything" }, nil)
    expect(data["caller"]).to include("attribution" => "anonymous")
    data, = call_tool("get_claim", { claim_id: SecureRandom.uuid })
    expect(data["hint"]).to include("request_feature")
  end

  it "lists claims by source and shows requests to moderators only" do
    bundle = JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about")
    bundle["sources"].each { |s| s["retrieved_at"] = Time.now.utc.iso8601 }
    data, err = call_tool("record_investigation", bundle)
    expect(err).to be(false), data.inspect
    source_id = data["ids"]["minutes"]
    data, err = call_tool("search_claims", { source_id: source_id })
    expect(err).to be(false), data.inspect
    expect(data["claims"].map { |c| c["id"] }).to include(*data["claims"].map { |c| c["id"] })
    expect(data["claims"].size).to be >= 1
    expect(data["claims"].map { |c| c["text"] }.join).to include("Brackenridge")

    call_tool("request_feature", { asked: "a", needed: "something the moderators should read" })
    post session_path, params: { email_address: user.email_address, password: password }
    get "/feature_requests"
    expect(response).to redirect_to(root_path)
    user.update!(moderator: true)
    get "/feature_requests"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("something the moderators should read")

    # One line each on the list; who filed it and what they expected are on the
    # entry's own screen (owner request, 2026-09-20).
    request = FeatureRequest.order(:created_at).last
    get "/feature_requests/#{request.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Claude").and include("something the moderators should read")

    patch "/feature_requests/#{request.id}", params: { status: "IGNORED", resolution: "Out of scope for v0.1." }
    expect(request.reload).to have_attributes(status: "IGNORED", resolution: "Out of scope for v0.1.")
    get "/feature_requests/#{request.id}"
    expect(response.body).to include("Out of scope for v0.1.")
    get "/feature_requests", params: { status: "OPEN" }
    expect(response.body).not_to include("something the moderators should read")
    get "/feature_requests", params: { status: "IGNORED" }
    expect(response.body).to include("something the moderators should read")

    patch "/feature_requests/#{request.id}", params: { status: "NONSENSE" }
    expect(request.reload.status).to eq("IGNORED")
  end
end
