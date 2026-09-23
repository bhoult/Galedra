require "rails_helper"

# Stage 42 §1 and §6: a call is checked against the schema it was handed, in
# the caller's vocabulary, and a refusal is never told less than a success.
RSpec.describe "Refusals from the schema a caller was handed (Stage 42)", type: :request do
  before { release_models }

  let(:curator) { register_key(display_name: "Curator").first }
  let(:user) { User.create!(email_address: "me@example.com", password: "correct horse battery staple") }
  let!(:token) { Assistants::Connect.call(user: user, name: "Claude", provider: "anthropic").last }

  def rpc(name, arguments, tok = token)
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["Authorization"] = "Bearer #{tok}" if tok
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json, headers: headers
    response.parsed_body
  end

  def indifferent(h) = h.is_a?(Hash) ? h.transform_keys(&:to_s) : h

  # A value of the wrong kind for a property, whatever the property is.
  def wrong_for(schema)
    schema = indifferent(schema)
    case schema["type"]
    when "array" then "not a list"
    when "object" then "not an object"
    when "integer" then "not a number"
    when "boolean" then "maybe"
    else schema["enum"] ? "NOT_ONE_OF_THEM" : { "an" => "object" }
    end
  end

  # Acceptance 1. Walks TOOLS, so a tool added later is covered without anybody
  # remembering to add it here.
  it "refuses, for every tool, a call that breaks its schema, naming the field and what it accepts" do
    without_arguments = []
    Mcp::Server::TOOLS.each do |tool|
      properties = indifferent(indifferent(tool[:inputSchema])["properties"] || {})
      if properties.empty?
        without_arguments << tool[:name]
        next
      end
      name, schema = properties.first
      required = Array(indifferent(tool[:inputSchema])["required"]).map(&:to_s)
      # Satisfy the other required keys with text, so the refusal is about the field under test.
      args = required.index_with { "x" }.merge(name => wrong_for(schema))
      body = rpc(tool[:name], args)
      errors = body.dig("result", "structuredContent", "errors") || []
      mine = errors.find { |e| e["path"] == "$.#{name}" }
      expect(mine).to be_present, "#{tool[:name]}: #{name} given the wrong kind was not refused by its schema (#{errors.inspect})"
      expect(mine["code"]).to eq("SCHEMA_INVALID")
      expect(mine["detail"]).to start_with("#{name} must be")
      expect(mine["see"]).to be_present, "#{tool[:name]}: the refusal should carry the part of the schema it broke"
    end
    expect(without_arguments).to contain_exactly("list_topics", "next_content_review", "next_affiliation_review")
  end

  # Acceptance 3: a float, a list, a bad enum and a missing nested field are each
  # refused by name before any envelope is built, so CanonicalJson's "use an
  # integer or a decimal string" never reaches a caller again.
  it "refuses the four shapes that used to be answered from deep inside, before anything is written" do
    count = Contribution.count
    link = { "evidence" => "e", "claim" => "c", "direction" => "SUPPORT", "strength" => "DIRECT", "steps" => 0 }
    base = { "statement" => "A statement.", "claims" => [ { "handle" => "c", "text" => "A claim.", "type" => "TEXTUAL" } ],
             "sources" => [ { "handle" => "s", "type" => "WEBSITE", "title" => "T", "url" => "https://example.test/", "retrieved_at" => Time.now.utc.iso8601 } ],
             "excerpts" => [ { "handle" => "x", "source" => "s", "text" => "A passage." } ],
             "evidence" => [ { "handle" => "e", "excerpt" => "x", "statement" => "It says so." } ] }
    cases = {
      "a float" => [ link.merge("strength" => 0.6), "$.links[0].strength", "links[0].strength must be one of DIRECT" ],
      "a list" => [ link.merge("steps" => %w[one two]), "$.links[0].steps", "links[0].steps must be a whole number; got a list" ],
      "a bad enum" => [ link.merge("direction" => "AGREES"), "$.links[0].direction", "links[0].direction must be one of" ],
      "a missing nested field" => [ link.except("evidence"), "$.links[0].evidence", "links[0].evidence is required and was not sent" ]
    }
    cases.each do |what, (bad, path, detail)|
      body = rpc("record_investigation", base.merge("links" => [ bad ]))
      errors = body.dig("result", "structuredContent", "errors")
      expect(errors&.map { |e| e["path"] }).to include(path), "#{what}: #{errors.inspect}"
      expect(errors.find { |e| e["path"] == path }["detail"]).to start_with(detail)
      expect(body.to_json).not_to include("decimal string"), "#{what}: CanonicalJson spoke to the caller"
    end
    expect(Contribution.count).to eq(count)
  end

  it "still accepts what the tools have always accepted" do
    schema = Mcp::Server::TOOLS.find { |t| t[:name] == "list_claims" }[:inputSchema]
    expect(Mcp::Arguments.errors(schema, { "section_id" => "x", "limit" => "5", "checkable" => "true", "state" => nil })).to eq([])
    expect(Mcp::Arguments.errors(schema, { "section_id" => "x", "limit" => 5.0, "unknown_alias" => [ 1 ] })).to eq([])
  end

  # Acceptance 7.
  it "tells a refused call as much as a successful one" do
    claim = create_claim(curator, "Remote work raises productivity.", type: "CAUSAL")
    ok = rpc("get_claim", { "claim_id" => claim.id }).dig("result", "structuredContent")
    refused = rpc("get_claim", { "claim_id" => "01a0cfff-0000-7000-8000-000000000000" }).dig("result", "structuredContent")
    expect(refused["errors"]).to be_present
    shared = %w[guidance waiting_on_you] & ok.keys
    expect(shared).to include("guidance")
    expect(refused.keys).to include(*shared), "a refusal was told less than a success: #{(shared - refused.keys).inspect}"
    expect(refused["guidance"]["topic"]).to eq(ok["guidance"]["topic"])
  end

  # Acceptance 8. Both authentication refusals: the server's, for a tool that
  # needs a token the connection does not hold, and the controller's 401, for a
  # token that is not usable at all — which is the one a caller with a stale
  # token actually meets.
  it "names every way in when a call carries no usable token, and each is a route this node serves" do
    _, body = Mcp::Server.new(token: nil, base_url: "http://www.example.com")
                         .handle({ "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call", "params" => { "name" => "get_report", "arguments" => { "report_id" => "01a0cfff" } } })
    server = body.dig(:result, :structuredContent, :errors).find { |e| e[:code] == "TOKEN_INVALID" }[:detail]
    rpc("get_report", { "report_id" => "01a0cfff" }, "gal_#{'x' * 32}")
    expect(response).to have_http_status(:unauthorized)
    controller = response.parsed_body.dig("error", "message")

    [ server, controller ].each do |detail|
      expect(detail).to include("/mcp/connect", "/connect", "/assistants/new", "/mcp/<token>", "adopt_url")
    end
    { "/mcp/connect" => :post, "/connect" => :get, "/assistants/new" => :get, "/mcp/gal_example_token_value" => :post }.each do |path, verb|
      expect { Rails.application.routes.recognize_path(path, method: verb) }.not_to raise_error, "#{verb.upcase} #{path} is named but not routed"
    end
  end

  # Audit, 2026-09-23: the similar-wording search costs time in proportion to the
  # text it compares, and both of these reached it with text of any length.
  it "refuses an over-long search query and an over-long claim before the similarity search runs" do
    expect(Claims::Duplicates).not_to receive(:candidates)
    refused = rpc("search_claims", { "query" => "word " * 100 })
    expect(refused.dig("result", "structuredContent", "errors").first).to include("code" => "SCHEMA_INVALID", "path" => "$.query")

    count = Contribution.count
    long = "A claim that goes on. " * 100
    body = rpc("record_investigation", { "statement" => "x", "claims" => [ { "handle" => "c", "text" => long, "type" => "TEXTUAL" } ] })
    expect(body.dig("result", "structuredContent", "errors").map { |e| e["path"] }).to include("$.claims[0].text")
    expect(Contribution.count).to eq(count)
  end
end
