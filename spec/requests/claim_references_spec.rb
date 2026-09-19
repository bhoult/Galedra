require "rails_helper"

RSpec.describe "Claim references: how often a claim is met (owner request, 2026-09-19)", type: :request do
  before { release_models }

  let(:user) { User.create!(email_address: "me@example.com", password: "correct horse battery staple") }
  let(:token) { Assistants::Connect.call(user: user, name: "Claude", provider: "anthropic").last }

  def call_tool(name, arguments)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }
    response.parsed_body.dig("result", "structuredContent")
  end

  def bundle
    b = JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about")
    b["sources"].each { |s| s["retrieved_at"] = Time.now.utc.iso8601 }
    b
  end

  it "counts checks, look-ups, views, and shares per claim and day, and orders the lists by them" do
    recorded = call_tool("record_investigation", bundle)
    expect(recorded["recorded"]).to be(true), recorded.inspect
    ids = recorded["claims"].map { |c| c["id"] }
    ids.each { |id| expect(ClaimReference.totals(id)).to include("CHECKED" => 1, "total" => 1) }

    first = ids.first
    data = call_tool("get_claim", { claim_id: first })
    expect(data["references"]).to include("CHECKED" => 1, "LOOKED_UP" => 1, "total" => 2)
    call_tool("explain", { claim_id: first })
    call_tool("fetch", { id: first })
    get "/claims/#{first}"
    expect(response.body).to include("Referenced 5 times: checked 1, looked up by assistants 3, viewed 1, shared 0")
    get "/claims/#{first}/card"
    get "/investigations/#{recorded['share']['url'].split('/').last}"
    totals = ClaimReference.totals(first)
    expect(totals).to include("VIEWED" => 1, "SHARED" => 2, "total" => 7)
    expect(ClaimReference.where(claim_id: first).count).to eq(4)

    get "/claims", params: { sort: "references" }
    expect(response.body).to include("a count of attention, not of truth or error")
    rows = response.body.scan(%r{/claims/([0-9a-f-]{36})}).flatten.uniq
    expect(rows.first).to eq(first)

    get "/api/v1/claims", params: { sort: "references", kind: "LOOKED_UP", window: "7d" }
    listed = response.parsed_body["claims"]
    expect(listed.first["id"]).to eq(first)
    expect(listed.first["references"]).to include("LOOKED_UP" => 3)
    get "/api/v1/claims/#{first}"
    expect(response.parsed_body.dig("claim", "references", "total")).to eq(7)
  end

  it "never lets a failed count break the page" do
    _, claim = register_key.then { |pair, _| [ pair, nil ] }
    allow(ClaimReference).to receive(:upsert_all).and_raise(ActiveRecord::StatementInvalid, "boom")
    expect(ClaimReference.count!(SecureRandom.uuid_v7, "VIEWED")).to be_nil
    expect { ClaimReference.count!(SecureRandom.uuid_v7, "NOPE") }.to raise_error(ArgumentError)
  end
end
