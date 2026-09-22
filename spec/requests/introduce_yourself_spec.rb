require "rails_helper"

# An assistant keyed by the address it calls from is a different assistant every
# time that address changes. Meta's Muse took 30 tokens across 26 source keys in
# two hours on 2026-09-22, wrote 77 identity entries to a log that cannot forget
# them, and could not read the answer to a report it had filed itself.
RSpec.describe "An assistant naming itself", type: :request do
  def call_tool(name, arguments, token: nil)
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["Authorization"] = "Bearer #{token}" if token
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                           params: { name: name, arguments: arguments } }.to_json, headers: headers
    response.parsed_body.dig("result", "structuredContent")
  end

  def introduce(name: "Muse", provider: "other", model: "muse-1")
    call_tool("introduce_yourself", { "name" => name, "provider" => provider, "model" => model }.compact)
  end

  it "hands back a token, both ways of sending it, and the adoption link" do
    data = introduce

    expect(data["errors"]).to be_nil
    expect(data["token"]).to start_with("gal_")
    expect(data["url"]).to end_with("/mcp/#{data['token']}")
    expect(data["header"]).to eq("Authorization: Bearer #{data['token']}")
    expect(data["adopt_url"]).to include("/adopt/")
  end

  it "records what the assistant said about itself" do
    introduce(name: "Muse", provider: "other", model: "muse-1")
    software = AssistantToken.order(:created_at).last.software

    expect(software["agent_name"]).to eq("Muse")
    expect(software["model_provider"]).to eq("other")
    expect(software["model_id"]).to eq("muse-1")
  end

  # The whole point: the same identity on every later call, whatever address it
  # arrives from. Without this the token is no better than the address-keyed one.
  it "is the same identity on a later call from anywhere" do
    token = introduce["token"]

    first = call_tool("list_topics", {}, token: token)
    expect(first["errors"]).to be_nil
    expect(AssistantToken.find_by(token_digest: AssistantToken.digest(token))).to be_present
  end

  # It grants identity, never authority. A caller with no token at all could
  # already do everything this token can do.
  it "still cannot work the task queue" do
    token = introduce["token"]
    data = call_tool("next_task", {}, token: token)

    expect(data["errors"].map { |e| e["code"] }).to include("TOKEN_INVALID")
    expect(data["errors"].first["detail"]).to include("a person behind it")
    expect(AssistantToken.order(:created_at).last).to be_anonymous
  end

  it "reads and contributes exactly as an unnamed caller does" do
    token = introduce["token"]

    expect(call_tool("list_tasks", {}, token: token)["errors"]).to be_nil
    expect(call_tool("search_claims", { "query" => "anything" }, token: token)["errors"]).to be_nil
  end

  # A name is the assistant's own statement about itself and is untrusted text
  # (Invariant 11): capped, and stripped of anything that is not a name.
  it "keeps a name to a name" do
    long = introduce(name: "A" * 500)
    expect(AssistantToken.order(:created_at).last.software["agent_name"].length).to eq(Mcp::Server::NAME_MAX)
    expect(long["errors"]).to be_nil

    introduce(name: "Bad\u0000\u0007 Name\nHere")
    expect(AssistantToken.order(:created_at).last.software["agent_name"]).to eq("Bad Name Here")
  end

  it "refuses a name that is not one, and a maker it does not know" do
    expect(introduce(name: "   ")["errors"].first["detail"]).to include("name is required and was sent empty")
    expect(introduce(provider: "acme")["errors"].first["path"]).to eq("$.provider")
  end

  # A mint costs three signed entries in a log that cannot forget them, so a
  # loop must not be able to take a thousand.
  it "stops a caller taking token after token" do
    Assistants::Introduce::PER_SOURCE_PER_DAY.times { expect(introduce["errors"]).to be_nil }
    over = introduce

    expect(over["errors"].map { |e| e["code"] }).to eq([ "DAILY_CAP" ])
    expect(over["errors"].first["detail"]).to include("keep the one you were given")
  end

  # The bound is keyed separately from `source_key`, which is how
  # `Connect.for_source` finds the shared anonymous token for an address. Writing
  # a self-minted token there would hand the next anonymous caller from that
  # address somebody else's credential.
  it "never becomes the token handed to the next anonymous caller" do
    token = introduce["token"]
    record = AssistantToken.find_by(token_digest: AssistantToken.digest(token))

    expect(record.source_key).to be_blank
    expect(record.mint_source_key).to be_present
    expect(AssistantToken.where(source_key: record.mint_source_key)).not_to include(record)
  end
end
