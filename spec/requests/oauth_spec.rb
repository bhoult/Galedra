require "rails_helper"

RSpec.describe "OAuth for connectors (Stage 16)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before { release_models }

  let(:json) { { "CONTENT_TYPE" => "application/json" } }
  let(:password) { "correct horse battery staple" }
  let!(:user) { User.create!(email_address: "me@example.com", password: password) }
  let(:verifier) { SecureRandom.urlsafe_base64(48) }
  let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }

  def register(name: "ChatGPT", method: "none")
    post "/oauth/register", params: { client_name: name, redirect_uris: [ "https://chatgpt.com/connector_platform_oauth_redirect" ], token_endpoint_auth_method: method }.to_json, headers: json
    expect(response).to have_http_status(:created)
    response.parsed_body
  end

  def sign_in
    post session_path, params: { email_address: user.email_address, password: password }
  end

  def authorize(client, scope: "galedra", state: "xyz")
    get "/oauth/authorize", params: { client_id: client["client_id"], redirect_uri: client["redirect_uris"].first, response_type: "code",
                                      code_challenge: challenge, code_challenge_method: "S256", scope: scope, state: state, resource: "http://www.example.com/mcp/connect" }
  end

  def approve(client)
    post "/oauth/authorize", params: { client_id: client["client_id"], redirect_uri: client["redirect_uris"].first, response_type: "code",
                                       code_challenge: challenge, code_challenge_method: "S256", scope: "galedra", state: "xyz", decision: "approve" }
    expect(response).to have_http_status(:found)
    location = URI.parse(response.headers["Location"])
    expect(location.host).to eq("chatgpt.com")
    query = URI.decode_www_form(location.query).to_h
    expect(query["state"]).to eq("xyz")
    expect(query["iss"]).to eq("http://www.example.com")
    query["code"]
  end

  def exchange(client, code, verifier: self.verifier, redirect_uri: client["redirect_uris"].first)
    post "/oauth/token", params: { grant_type: "authorization_code", code: code, redirect_uri: redirect_uri, client_id: client["client_id"], code_verifier: verifier }
    response.parsed_body
  end

  def mcp(token, method, params = {})
    headers = json.merge("Authorization" => "Bearer #{token}")
    post "/mcp/connect", params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json, headers: headers
    response.parsed_body
  end

  it "matches loopback redirects with the port ignored, as Claude Code needs" do
    post "/oauth/register", params: { client_name: "Claude Code", redirect_uris: [ "http://localhost/callback", "http://127.0.0.1/callback" ] }.to_json, headers: json
    client = response.parsed_body
    record = OauthClient.find_by!(client_id: client["client_id"])
    expect(record.redirect_uri_allowed?("http://localhost:3118/callback")).to be(true)
    expect(record.redirect_uri_allowed?("http://127.0.0.1:52001/callback")).to be(true)
    expect(record.redirect_uri_allowed?("http://localhost:3118/other")).to be(false)
    expect(record.redirect_uri_allowed?("https://evil.example/callback")).to be(false)
    get "/oauth/authorize", params: { client_id: client["client_id"], redirect_uri: "http://localhost:3118/callback", response_type: "code", code_challenge: challenge, code_challenge_method: "S256", scope: "galedra offline_access" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("return to <strong>localhost</strong>")
  end

  it "publishes valid discovery documents (#1)" do
    get "/.well-known/oauth-authorization-server"
    doc = response.parsed_body
    expect(doc).to include("issuer" => "http://www.example.com", "authorization_endpoint" => "http://www.example.com/oauth/authorize",
                           "token_endpoint" => "http://www.example.com/oauth/token", "registration_endpoint" => "http://www.example.com/oauth/register",
                           "revocation_endpoint" => "http://www.example.com/oauth/revoke", "code_challenge_methods_supported" => [ "S256" ])
    expect(doc["grant_types_supported"]).to contain_exactly("authorization_code", "refresh_token")
    expect(doc).to include("authorization_response_iss_parameter_supported" => true, "client_id_metadata_document_supported" => false)

    get "/.well-known/openid-configuration"
    expect(response.parsed_body["token_endpoint"]).to eq("http://www.example.com/oauth/token")

    get "/.well-known/oauth-protected-resource/mcp/connect"
    expect(response.parsed_body).to include("resource" => "http://www.example.com/mcp/connect", "authorization_servers" => [ "http://www.example.com" ])

    post "/mcp/connect", params: { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }.to_json, headers: json
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to include('resource_metadata="http://www.example.com/.well-known/oauth-protected-resource/mcp/connect"')
    expect(response.headers["WWW-Authenticate"]).to include('scope="galedra"')
  end

  it "registers, authorizes after sign-in, exchanges the code, and records attributed to the person (#2)" do
    client = register
    expect(client).to include("token_endpoint_auth_method" => "none")
    expect(client).not_to have_key("client_secret")

    authorize(client)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Connect ChatGPT to Galedra?")
    expect(response.body).to include("Sign in and connect under my name")
    post "/oauth/authorize", params: { client_id: client["client_id"], redirect_uri: client["redirect_uris"].first, response_type: "code",
                                       code_challenge: challenge, code_challenge_method: "S256", scope: "galedra", state: "xyz", decision: "approve" }
    expect(response).to redirect_to("/session/new")
    sign_in
    expect(response.headers["Location"]).to include("/oauth/authorize?")
    authorize(client)
    expect(response.body).to include("Connect under my name")
    expect(response.body).to include("Connect anonymously")
    expect(response.body).to include("optional")
    expect(response.body).to include("record investigations")

    code = approve(client)
    tokens = exchange(client, code)
    expect(response).to have_http_status(:ok)
    expect(tokens).to include("token_type" => "Bearer", "scope" => "galedra")
    expect(tokens["access_token"]).to start_with("gat_")
    expect(tokens["refresh_token"]).to start_with("grt_")

    assistant = AssistantToken.find_by!(user: user)
    expect(assistant.software).to include("agent_name" => "ChatGPT", "model_provider" => "openai", "oauth_client_id" => client["client_id"])
    expect(assistant.principal).to eq(user.custodied_key.contributor)
    expect(Contribution.where(action_type: "DELEGATE", signer_key_id: assistant.principal.key_id).count).to eq(1)

    init = mcp(tokens["access_token"], "initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "spec", version: "0" } })
    expect(init.dig("result", "serverInfo", "name")).to eq("galedra")
    bundle = JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about")
    bundle["sources"].each { |s| s["retrieved_at"] = "2026-09-18T12:00:00Z" }
    result = mcp(tokens["access_token"], "tools/call", { name: "record_investigation", arguments: bundle }).dig("result", "structuredContent")
    expect(result["recorded"]).to be(true)
    expect(result["attribution"]).to include("anonymous" => false, "principal" => "a named contributor")
    expect(Claim.find(result["claims"].first["id"]).contribution.principal_contributor).to eq(user.custodied_key.contributor)

    post "/api/v1/investigations", params: bundle.merge("claims" => [ { "handle" => "z", "text" => "Attributed over REST.", "type" => "TEXTUAL" } ], "links" => [], "evidence" => [], "excerpts" => [], "sources" => []).to_json,
                                    headers: json.merge("Authorization" => "Bearer #{tokens['access_token']}")
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig("attribution", "anonymous")).to be(false)

    # A second grant reuses the same delegation.
    authorize(client)
    exchange(client, approve(client))
    expect(AssistantToken.where(user: user).count).to eq(1)
  end

  it "refuses a wrong verifier, a reused code, a mismatched redirect, an unknown client, and an expired access token (#3)" do
    client = register
    sign_in
    code = approve(client)

    exchange(client, code, verifier: "wrong")
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]).to eq("invalid_grant")

    good = exchange(client, code)
    expect(response).to have_http_status(:ok)
    exchange(client, code)
    expect(response.parsed_body["error"]).to eq("invalid_grant")

    code2 = approve(client)
    exchange(client, code2, redirect_uri: "https://chatgpt.com/elsewhere")
    expect(response.parsed_body["error"]).to eq("invalid_grant")

    post "/oauth/token", params: { grant_type: "authorization_code", code: code2, redirect_uri: client["redirect_uris"].first, client_id: "gci_nope", code_verifier: verifier }
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body["error"]).to eq("invalid_client")

    get "/oauth/authorize", params: { client_id: client["client_id"], redirect_uri: "https://evil.example/cb", response_type: "code", code_challenge: challenge, code_challenge_method: "S256" }
    expect(response).to have_http_status(:bad_request)
    expect(response.body).to include("not registered")

    # Owner decision: tokens do not expire.
    travel_to(2.years.from_now) do
      mcp(good["access_token"], "initialize", {})
      expect(response).to have_http_status(:ok)
    end
    expect(good).not_to have_key("expires_in")
  end

  it "lets the person continue anonymously on the consent page, with an adoptable anonymous key" do
    client = register(name: "Claude")
    authorize(client)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Continue anonymously")
    expect(response.body).to include("Sign in and connect under my name")

    post "/oauth/authorize", params: { client_id: client["client_id"], redirect_uri: client["redirect_uris"].first, response_type: "code",
                                       code_challenge: challenge, code_challenge_method: "S256", scope: "galedra", state: "anon", decision: "anonymous" }
    location = URI.parse(response.headers["Location"])
    code = URI.decode_www_form(location.query).to_h["code"]
    tokens = exchange(client, code)
    expect(response).to have_http_status(:ok)

    bundle = JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about")
    bundle["sources"].each { |s| s["retrieved_at"] = "2026-09-18T12:00:00Z" }
    result = mcp(tokens["access_token"], "tools/call", { name: "record_investigation", arguments: bundle }).dig("result", "structuredContent")
    expect(result["recorded"]).to be(true)
    expect(result["attribution"]["anonymous"]).to be(true)
    expect(result["attribution"]["adopt_url"]).to include("/adopt/")
    assistant = OauthToken.find_by!(kind: "access", token_digest: OauthToken.digest(tokens["access_token"])).assistant_token
    expect(assistant.principal).to be_anonymous
    expect(assistant.software["agent_name"]).to eq("Claude")

    # Choosing to sign in first sends the person to sign-in and back to the same request.
    post "/oauth/authorize", params: { client_id: client["client_id"], redirect_uri: client["redirect_uris"].first, response_type: "code",
                                       code_challenge: challenge, code_challenge_method: "S256", scope: "galedra", state: "later", decision: "approve" }
    expect(response).to redirect_to("/session/new")
    sign_in
    expect(response.headers["Location"]).to include("/oauth/authorize?")
    expect(response.headers["Location"]).to include("state=later")
  end

  it "honours a read-only grant: reads work, writes are refused with insufficient_scope" do
    client = register
    sign_in
    post "/oauth/authorize", params: { client_id: client["client_id"], redirect_uri: client["redirect_uris"].first, response_type: "code",
                                       code_challenge: challenge, code_challenge_method: "S256", scope: "galedra:read", state: "s", decision: "approve" }
    code = URI.decode_www_form(URI.parse(response.headers["Location"]).query).to_h["code"]
    tokens = exchange(client, code)
    expect(tokens["scope"]).to eq("galedra:read")

    listing = mcp(tokens["access_token"], "tools/list", {})
    expect(listing.dig("result", "tools").size).to be >= 8
    result = mcp(tokens["access_token"], "tools/call", { name: "record_investigation", arguments: { "claims" => [ { "handle" => "c", "text" => "Read only.", "type" => "TEXTUAL" } ] } })
    expect(result.dig("result", "isError")).to be(true)
    expect(result.dig("result", "structuredContent", "errors").first["code"]).to eq("INSUFFICIENT_SCOPE")

    post "/api/v1/investigations", params: { claims: [ { handle: "c", text: "Read only.", type: "TEXTUAL" } ] }.to_json, headers: json.merge("Authorization" => "Bearer #{tokens['access_token']}")
    expect(response).to have_http_status(:forbidden)
    expect(response.headers["WWW-Authenticate"]).to include("insufficient_scope")
  end

  it "rotates refresh tokens and revokes the family on replay (#4)" do
    client = register(name: "Claude", method: "client_secret_post")
    expect(client["client_secret"]).to start_with("gcs_")
    sign_in
    first = exchange(client, approve(client))
    expect(response).to have_http_status(:unauthorized)

    post "/oauth/token", params: { grant_type: "authorization_code", code: approve(client), redirect_uri: client["redirect_uris"].first, client_id: client["client_id"], client_secret: client["client_secret"], code_verifier: verifier }
    first = response.parsed_body
    expect(response).to have_http_status(:ok)

    post "/oauth/token", params: { grant_type: "refresh_token", refresh_token: first["refresh_token"], client_id: client["client_id"], client_secret: client["client_secret"] }
    second = response.parsed_body
    expect(second["access_token"]).not_to eq(first["access_token"])
    mcp(first["access_token"], "initialize", {})
    expect(response).to have_http_status(:unauthorized)
    mcp(second["access_token"], "initialize", {})
    expect(response).to have_http_status(:ok)

    post "/oauth/token", params: { grant_type: "refresh_token", refresh_token: first["refresh_token"], client_id: client["client_id"], client_secret: client["client_secret"] }
    expect(response.parsed_body["error"]).to eq("invalid_grant")
    mcp(second["access_token"], "initialize", {})
    expect(response).to have_http_status(:unauthorized)
    expect(AssistantToken.find_by!(user: user)).to be_usable
  end

  it "disconnecting on the connect page revokes the delegation and every token, and the log still verifies (#5)" do
    client = register
    sign_in
    tokens = exchange(client, approve(client))
    assistant = AssistantToken.find_by!(user: user)

    get "/assistants/new"
    expect(response.body).to include("ChatGPT")
    delete "/assistants/#{assistant.id}"
    expect(response).to redirect_to("/assistants/new")
    expect(Contribution.where(action_type: "REVOKE_DELEGATION").count).to eq(1)
    mcp(tokens["access_token"], "initialize", {})
    expect(response).to have_http_status(:unauthorized)
    post "/oauth/token", params: { grant_type: "refresh_token", refresh_token: tokens["refresh_token"], client_id: client["client_id"] }
    expect(response.parsed_body["error"]).to eq("invalid_grant")

    post "/oauth/revoke", params: { token: tokens["access_token"], client_id: client["client_id"] }
    expect(response).to have_http_status(:ok)
    expect(Ledger::Verify.call.status).to eq("CHAIN_VERIFIED")
    before = Ledger::TableDigest.projections
    Ledger::Replay.call
    expect(Ledger::TableDigest.projections).to eq(before)
  end
end
