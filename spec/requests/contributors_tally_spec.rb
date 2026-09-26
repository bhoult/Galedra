require "rails_helper"

RSpec.describe "Work done per contributor and the contributors list (owner request, 2026-09-19)", type: :request do
  include GraphHelpers
  before { release_models }

  let(:password) { "correct horse battery staple" }
  let(:user) { User.create!(email_address: "me@example.com", password: password) }
  let(:token) { Assistants::Connect.call(user: user, name: "Claude", provider: "anthropic").last }

  def call_tool(name, arguments, tok = token)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{tok}" }
    response.parsed_body.dig("result", "structuredContent")
  end

  it "credits an assistant's recorded work, reviews, and tasks to the person it acts for, and lists the top contributors" do
    bundle = JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about")
    bundle["sources"].each { |s| s["retrieved_at"] = Time.now.utc.iso8601 }
    data = call_tool("record_investigation", bundle)
    expect(data["recorded"]).to be(true), data.inspect
    principal = AssistantToken.find_by_token(token).principal
    tally = Contributors::Tally.for(principal.id)
    expect(tally[:recorded]).to eq(data["contributions"])
    expect(tally[:total]).to eq(data["contributions"])

    BugReport.record!(happened: "something broke")
    item = ContentReview.pending.first
    item.vote!(AssistantToken.find_by_token(token), "CLEAN")
    expect(Contributors::Tally.for(principal.id)[:reviews]).to eq(1)

    pair, other = register_key
    create_claim(pair, "A claim by someone else.")
    rows = Contributors::Tally.top
    expect(rows.first.first).to eq(principal)
    expect(rows.map(&:first)).to include(other)
    expect(rows.map(&:first).map(&:kind)).not_to include(Contributor::SYSTEM)

    get "/contributors"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Counts of work done, not of reliability")
    expect(response.body.index(principal.display_name.presence || principal.key_id[-8..])).to be < response.body.index(other.key_id[0, 8]).to_i + 1_000_000
    get "/contributors/#{principal.id}"
    expect(response.body).to include("Work done").and include("1 reviews")
    get "/api/v1/contributors/top"
    expect(response.parsed_body["contributors"].first["work"]["total"]).to eq(tally[:total] + 1)
    get "/api/v1/contributors/#{principal.id}"
    expect(response.parsed_body.dig("contributor", "work", "reviews")).to eq(1)
    get "/contributors", params: { window: "30d" }
    expect(response).to have_http_status(:ok)

    post "/session", params: { email_address: user.email_address, password: password }
    get "/account"
    expect(response.body).to include("Your work")
  end

  it "counts work done anonymously as one row, because each connection mints its own key" do
    3.times do |i|
      anonymous_token = Assistants::Connect.call(name: "Assistant #{i}", provider: "anthropic").last
      post "/api/v1/custodied/contributions",
           params: { action_type: "CREATE_CLAIM", payload: claim_payload("An anonymous claim #{i}.") }.to_json,
           headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{anonymous_token}" }
      expect(response).to have_http_status(:created)
    end
    pair, named = register_key(display_name: "Named")
    4.times { |i| create_claim(pair, "A named claim #{i}.") }

    rows = Contributors::Tally.top
    folded = rows.select { |c, _| c.identity_tier == "ANONYMOUS" }
    expect(folded.size).to eq(1)
    row, work = folded.first
    expect(row.principals).to eq(3)
    expect(row.id).to be_nil, "an anonymous row stands for no one key, so it has no page"
    expect(work).to include(recorded: 3, total: 3)
    expect(rows.first.first).to eq(named), "the fold does not change the order; four beats three"

    get "/contributors"
    expect(response).to have_http_status(:ok)
    expect(response.body.scan("across 3 keys").size).to eq(1)
    expect(response.body).to include("Work done anonymously is one row")

    get "/api/v1/contributors/top"
    anonymous_rows = response.parsed_body["contributors"].select { |r| r["anonymous"] }
    expect(anonymous_rows.size).to eq(1)
    expect(anonymous_rows.first).to include("id" => nil, "key_id" => nil, "display_name" => "Anonymous", "principals" => 3)
    expect(anonymous_rows.first.dig("work", "total")).to eq(3)
  end
end
