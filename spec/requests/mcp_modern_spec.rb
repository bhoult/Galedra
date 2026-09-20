require "rails_helper"

# Stage 32: revision 2026-07-28 alongside the 2025-06-18 handshake. The legacy
# path is covered by mcp_spec.rb, and that it still passes unchanged is the point
# of this stage; what is checked here is the modern path and the boundary
# between them.
RSpec.describe "MCP, modern era (Stage 32)", type: :request do
  before { release_models }

  # Methods rather than constants: a constant assigned inside a describe block
  # is defined on Object, not on the example group, so it leaks to every other
  # spec in the run.
  def modern_version = Mcp::Era::MODERN

  def default_meta
    { Mcp::Era::VERSION_KEY => modern_version,
      Mcp::Era::CLIENT_INFO_KEY => { "name" => "ExampleClient", "version" => "1.0.0" },
      Mcp::Era::CAPABILITIES_KEY => {} }
  end

  # A modern client: no handshake, every request carrying its own metadata, and
  # the headers that mirror the body for intermediaries.
  def modern(method, params = {}, id: 1, version: modern_version, headers: {}, meta: default_meta)
    body = { jsonrpc: "2.0", id: id, method: method, params: params.merge("_meta" => meta) }
    sent = { "CONTENT_TYPE" => "application/json",
             "ACCEPT" => "application/json, text/event-stream",
             "MCP-Protocol-Version" => version,
             "Mcp-Method" => method }
    sent["Mcp-Name"] = params["name"] if params["name"]
    post "/mcp", params: body.to_json, headers: sent.merge(headers).compact
    response.parsed_body
  end

  def legacy(method, params = {})
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body
  end

  describe "acceptance 1: the legacy handshake is untouched" do
    it "answers initialize with the same fields and announces 2025-06-18" do
      result = legacy("initialize")["result"]
      expect(result["protocolVersion"]).to eq("2025-06-18")
      expect(result["serverInfo"]).to eq({ "name" => "galedra", "version" => Mcp::Server::VERSION })
      expect(result["capabilities"]).to eq({ "tools" => { "listChanged" => false } })
      expect(result["instructions"]).to include("Galedra is a public, signed record")
      expect(result).not_to have_key("resultType"), "a legacy result must look exactly as it did"
      expect(response.headers["MCP-Protocol-Version"]).to eq("2025-06-18")
    end
  end

  describe "acceptance 2: a modern request is served with no handshake before it" do
    it "carries resultType and identifies the server on the response itself" do
      body = modern("tools/list")
      expect(response).to have_http_status(:ok)
      expect(body["result"]["resultType"]).to eq("complete")
      expect(body["result"].dig("_meta", Mcp::Era::SERVER_INFO_KEY))
        .to eq({ "name" => "galedra", "version" => Mcp::Server::VERSION })
      expect(body["result"]["tools"]).to be_present
      expect(response.headers["MCP-Protocol-Version"]).to eq(modern_version)
    end

    it "calls a tool without any prior request establishing anything" do
      body = modern("tools/call", { "name" => "list_topics", "arguments" => {} })
      expect(body["result"]["resultType"]).to eq("complete")
      expect(body["result"]["isError"]).to be_falsey
    end

    # A refusal is a completed call whose tool reported an error, so it carries
    # resultType like any other result. It did not: only the success path went
    # through `decorate`, so every Ledger::Rejected and every DAILY_CAP reached a
    # modern client as a malformed frame and the reason never arrived. The test
    # above passed throughout, because its second line asserts isError is falsey
    # — it pinned the happy path and said in the same breath that this one was
    # out of scope (docs/experiments/2026-09-20-second-connector-run.md).
    it "sends a refusal as a well-formed result carrying its reason" do
      body = modern("tools/call", { "name" => "get_claim", "arguments" => { "claim_id" => SecureRandom.uuid } })

      expect(body["result"]["isError"]).to be(true)
      expect(body["result"]["resultType"]).to eq("complete"), "a refused call still completed"
      expect(body["result"].dig("_meta", Mcp::Era::SERVER_INFO_KEY, "name")).to eq("galedra")
      expect(body["result"].dig("structuredContent", "errors").first).to include("code" => "NOT_FOUND")
      expect(body["result"].dig("content", 0, "text")).to include("NOT_FOUND", "no such claim")
    end
  end

  describe "acceptance 3: server/discover" do
    it "lists both supported versions, the capabilities and the identity" do
      result = modern("server/discover")["result"]
      expect(result["supportedVersions"]).to eq([ modern_version, "2025-06-18" ])
      expect(result["capabilities"]).to eq({ "tools" => { "listChanged" => false } })
      expect(result.dig("_meta", Mcp::Era::SERVER_INFO_KEY, "name")).to eq("galedra")
      expect(result["instructions"]).to include("Galedra is a public, signed record")
    end

    # Unlike tools/list, this may be cached: every field is fixed for the life of
    # the process, so no missing push notification can leave a client wrong. It
    # was 0, and a client re-probed at every turn boundary for the same answer.
    it "may be cached for an hour, where tools/list may not be" do
      result = modern("server/discover")["result"]
      expect(result["ttlMs"]).to eq(3_600_000)
      expect(result["cacheScope"]).to eq("public")
      expect(modern("tools/list")["result"]["ttlMs"]).to eq(0), "a tool description can change with no way to announce it"
    end
  end

  describe "acceptance 4: a version this server will not serve" do
    it "returns -32022 with what it does support, at 400" do
      body = modern("tools/list", version: "1900-01-01",
                    meta: default_meta.merge(Mcp::Era::VERSION_KEY => "1900-01-01"))
      expect(response).to have_http_status(:bad_request)
      expect(body["error"]["code"]).to eq(-32022)
      expect(body["error"]["data"]).to eq({ "supported" => [ modern_version, "2025-06-18" ], "requested" => "1900-01-01" })
    end

    it "does not reject a legacy client that names an older version in the header" do
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json,
                   headers: { "CONTENT_TYPE" => "application/json", "MCP-Protocol-Version" => "2025-03-26" }
      expect(response).to have_http_status(:ok), "declaring _meta is what selects modern, not the header alone"
      expect(response.parsed_body["result"]["tools"]).to be_present
    end
  end

  describe "acceptance 5: caching hints in both eras" do
    it "sends ttlMs and cacheScope to a modern client" do
      result = modern("tools/list")["result"]
      expect(result["ttlMs"]).to eq(0)
      expect(result["cacheScope"]).to eq("public")
    end

    it "sends them to a legacy client too" do
      result = legacy("tools/list")["result"]
      expect(result["ttlMs"]).to eq(0)
      expect(result["cacheScope"]).to eq("public")
    end
  end

  describe "header and body must agree" do
    it "rejects a protocol version header that contradicts the body" do
      body = modern("tools/list", headers: { "MCP-Protocol-Version" => "2025-06-18" })
      expect(response).to have_http_status(:bad_request)
      expect(body["error"]["code"]).to eq(-32020)
    end

    it "rejects a missing Mcp-Method header" do
      body = modern("tools/list", headers: { "Mcp-Method" => nil })
      expect(response).to have_http_status(:bad_request)
      expect(body["error"]["code"]).to eq(-32020)
    end

    it "rejects an Mcp-Name that does not match the tool being called" do
      body = modern("tools/call", { "name" => "list_topics", "arguments" => {} },
                    headers: { "Mcp-Name" => "something_else" })
      expect(response).to have_http_status(:bad_request)
      expect(body["error"]["code"]).to eq(-32020)
    end

    it "accepts an Mcp-Name sent in the base64 sentinel form" do
      encoded = "=?base64?#{Base64.strict_encode64('list_topics')}?="
      body = modern("tools/call", { "name" => "list_topics", "arguments" => {} },
                    headers: { "Mcp-Name" => encoded })
      expect(response).to have_http_status(:ok)
      expect(body["result"]["resultType"]).to eq("complete")
    end
  end

  describe "required per-request metadata" do
    it "rejects a modern request with no protocol version in _meta" do
      body = modern("tools/list", meta: default_meta.except(Mcp::Era::VERSION_KEY))
      expect(response).to have_http_status(:bad_request)
      expect(body["error"]["code"]).to eq(-32602)
    end

    it "rejects a modern request that omits client capabilities" do
      body = modern("tools/list", meta: default_meta.except(Mcp::Era::CAPABILITIES_KEY))
      expect(response).to have_http_status(:bad_request)
      expect(body["error"]["code"]).to eq(-32602)
    end
  end

  describe "an unknown method" do
    it "is 404 for a modern client, so it can tell this from a wrong endpoint" do
      body = modern("nonsense/method")
      expect(response).to have_http_status(:not_found)
      expect(body["error"]["code"]).to eq(-32601)
    end

    it "stays 200 for a legacy client, which is what it expects" do
      body = legacy("nonsense/method")
      expect(response).to have_http_status(:ok)
      expect(body["error"]["code"]).to eq(-32601)
    end
  end

  describe "the removed GET stream" do
    it "is 405, which both revisions want from a server that pushes nothing" do
      get "/mcp"
      expect(response).to have_http_status(:method_not_allowed)
    end
  end
end
