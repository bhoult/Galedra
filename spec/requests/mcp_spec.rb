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
    expect(tools).to contain_exactly("search_claims", "get_claim", "record_investigation", "add_evidence", "explain", "share_card")

    data, err = call_tool("search_claims", { query: "Brackenridge bicycles" })
    expect(err).to be(false)
    expect(data["claims"]).to eq([])

    data, err = call_tool("record_investigation", bundle)
    expect(err).to be(true)
    expect(data["errors"].first["code"]).to eq("TOKEN_INVALID")

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
end
