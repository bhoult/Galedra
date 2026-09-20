require "rails_helper"

RSpec.describe "MCP endpoint (Stage 14)", type: :request do
  before { release_models }

  let(:token) { Assistants::Connect.call(name: "Claude", provider: "anthropic").last }

  # A minimal MCP client: one JSON-RPC message per POST.
  def rpc(method, params = {}, id: 1, token: nil)
    headers = { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json, text/event-stream" }
    headers["Authorization"] = "Bearer #{token}" if token
    post "/mcp", params: { jsonrpc: "2.0", id: id, method: method, params: params }.to_json, headers: headers
    response.body.present? ? response.parsed_body : nil
  end

  def call_tool(name, arguments, token: nil)
    body = rpc("tools/call", { name: name, arguments: arguments }, token: token)
    [ body.dig("result", "structuredContent"), body.dig("result", "isError") ]
  end

  def bundle
    JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about").tap do |b|
      b["sources"].each { |s| s["retrieved_at"] = Time.now.utc.iso8601 }
    end
  end

  it "initializes, lists the tools, records a bundle, and reads the card back under one token (#1)" do
    init = rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "spec", version: "0" } })
    expect(init.dig("result", "protocolVersion")).to eq("2025-06-18")
    expect(init.dig("result", "serverInfo", "name")).to eq("galedra")
    expect(init.dig("result", "instructions")).to include("never fetches URLs")
    expect(response.headers["MCP-Protocol-Version"]).to eq("2025-06-18")

    rpc("notifications/initialized")
    expect(response).to have_http_status(:accepted)

    tools = rpc("tools/list").dig("result", "tools").map { |t| t["name"] }
    expect(tools).to contain_exactly("search_claims", "get_claim", "record_investigation", "add_evidence", "explain", "share_card", "search", "fetch", "tag_claim", "list_topics",
                                     "list_tasks", "next_task", "submit_task", "release_task",
                                     "revise_claim", "merge_claims", "revise_link", "open_task", "list_proposals", "accept_proposal", "request_feature", "report_bug", "next_content_review", "submit_content_review", "next_affiliation_review", "submit_affiliation_review", "create_outline", "get_outline", "record_inference")

    data, err = call_tool("search_claims", { query: "Brackenridge bicycles" })
    expect(err).to be(false)
    expect(data["claims"]).to eq([])

    # Without a token the write still lands, as an anonymous assistant keyed to the caller.
    data, err = call_tool("record_investigation", bundle.merge("claims" => [ { "handle" => "t", "text" => "A tokenless MCP claim.", "type" => "TEXTUAL" } ], "links" => [], "evidence" => [], "excerpts" => [], "sources" => []))
    expect(err).to be(false)
    expect(Claim.find(data["claims"].first["id"]).contribution.principal_contributor).to be_anonymous
    expect(AssistantToken.find_by(source_key: Digest::SHA256.hexdigest("127.0.0.1|#{Date.current}"))).to be_present

    data, err = call_tool("record_investigation", bundle, token: token)
    expect(err).to be(false)
    expect(data["recorded"]).to be(true)
    ban = data["claims"].find { |c| c["handle"] == "ban" }

    data, = call_tool("search_claims", { query: "Brackenridge bicycles" })
    expect(data["claims"].map { |c| c["id"] }).to include(ban["id"])

    data, = call_tool("get_claim", { claim_id: ban["id"] })
    expect(data.dig("card", "plain", "headline")).to match(/against/)
    expect(data["url"]).to end_with("/claims/#{ban['id']}")

    data, = call_tool("explain", { claim_id: ban["id"], calculation: true })
    expect(data.dig("calculation", "stated_as")).to include("under ledger-default@0.1.0 at snapshot")
    expect(data.dig("why", "strongest_contradiction", "statement")).to include("Motion 14")

    data, = call_tool("share_card", { claim_id: ban["id"] })
    expect(data["image_url"]).to end_with("/claims/#{ban['id']}/card.png")

    data, = call_tool("search", { query: "Brackenridge bicycles" })
    expect(data["results"].map { |r| r["id"] }).to include(ban["id"])
    expect(data["results"].first["title"]).to include("—")
    data, = call_tool("fetch", { id: ban["id"] })
    expect(data["text"]).to include("Galedra says: The evidence leans against this.")
    expect(data["text"]).to include("Strongest contradiction: Motion 14")
    expect(data["metadata"]["assessment_state"]).to eq("LEANS_CONTRADICTED")

    data, err = call_tool("add_evidence", { claim_id: ban["id"], source: bundle["sources"].last.except("handle"), excerpt: "Bicycles may be walked.", statement: "Bicycles may still be walked on the mall.", direction: "QUALIFY" }, token: token)
    expect(err).to be(false)
    expect(data["claims"].first).to include("id" => ban["id"], "created" => false)
  end

  it "answers protocol errors the JSON-RPC way and refuses GET" do
    body = rpc("no/such", {}, id: 7)
    expect(body["error"]).to include("code" => -32601)
    expect(body["id"]).to eq(7)

    body = rpc("tools/call", { name: "nope", arguments: {} })
    expect(body["error"]["code"]).to eq(-32602)

    post "/mcp", params: "{oops", headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]["code"]).to eq(-32700)

    post "/mcp", params: [ 1, 2 ].to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:bad_request)

    get "/mcp"
    expect(response).to have_http_status(:method_not_allowed)
  end

  it "accepts the token in the URL for connector screens that take only a URL" do
    post "/mcp/#{token}", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "record_investigation", arguments: bundle } }.to_json,
                          headers: { "CONTENT_TYPE" => "application/json" }
    expect(response.parsed_body.dig("result", "isError")).to be(false)
    expect(response.parsed_body.dig("result", "structuredContent", "recorded")).to be(true)

    # A presented but invalid credential is refused outright, so an OAuth client refreshes instead of falling through to anonymous use.
    post "/mcp/gal_wrong", params: { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "record_investigation", arguments: bundle } }.to_json,
                           headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body.dig("error", "code")).to eq(-32001)
    expect(response.headers["WWW-Authenticate"]).to include("oauth-protected-resource")
  end
  # Stage 31. This server cannot push notifications/tools/list_changed: there is
  # no stream to push it on. So it must tell clients not to cache the tool list,
  # or a corrected description waits for a reconnect that may never come.
  it "declares no listChanged and asks clients not to cache the tool list" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json" }
    caps = response.parsed_body.dig("result", "capabilities", "tools")
    expect(caps["listChanged"]).to be(false)

    post "/mcp", params: { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json" }
    result = response.parsed_body["result"]
    expect(result["ttlMs"]).to eq(0)
    expect(result["cacheScope"]).to eq("public")

    get "/mcp"
    expect(response).to have_http_status(:method_not_allowed), "a stream would make listChanged: true honest; there is none"
  end
  # An assistant filed a feature request: the rules arrive verbatim on every
  # result, identical each time, and a long pass pays for them on every call.
  # They ride on every result on purpose, because that is the only channel
  # nothing caches. So a caller that has read them can say which version it
  # holds, and the default stays unchanged for one that says nothing.
  it "sends the rules until a caller says which version it already has" do
    body = rpc("tools/call", { name: "list_tasks", arguments: {} })
    guidance = body.dig("result", "structuredContent", "guidance")
    expect(guidance["version"]).to eq(Guidance::VERSION)
    expect(guidance["text"]).to be_present
    expect(guidance["repeat"]).to include("guidance_version")

    body = rpc("tools/call", { name: "list_tasks", arguments: { "guidance_version" => Guidance::VERSION } })
    quiet = body.dig("result", "structuredContent", "guidance")
    expect(quiet["version"]).to eq(Guidance::VERSION)
    expect(quiet["unchanged"]).to be(true)
    expect(quiet).not_to have_key("text")

    body = rpc("tools/call", { name: "list_tasks", arguments: { "guidance_version" => "1999-01-01" } })
    stale = body.dig("result", "structuredContent", "guidance")
    expect(stale["text"]).to be_present, "a stale version must still be corrected"
  end
end
