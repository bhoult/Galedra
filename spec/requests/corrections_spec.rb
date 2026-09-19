require "rails_helper"

RSpec.describe "Corrections from a connector and the claim page (Stage 19)", type: :request do
  before { release_models }

  let(:password) { "correct horse battery staple" }
  let(:alice) { User.create!(email_address: "alice@example.com", password: password) }
  let(:bob) { User.create!(email_address: "bob@example.com", password: password) }
  let(:carol) { User.create!(email_address: "carol@example.com", password: password) }
  let!(:alice_token) { Assistants::Connect.call(user: alice, name: "Claude", provider: "anthropic").last }
  let!(:bob_token) { Assistants::Connect.call(user: bob, name: "ChatGPT", provider: "openai").last }
  let!(:carol_token) { Assistants::Connect.call(user: carol, name: "Claude", provider: "anthropic").last }

  def rpc(method, params, token)
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["Authorization"] = "Bearer #{token}" if token
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json, headers: headers
    response.parsed_body
  end

  def call_tool(name, arguments, token)
    body = rpc("tools/call", { name: name, arguments: arguments }, token)
    [ body.dig("result", "structuredContent"), body.dig("result", "isError") ]
  end

  def codes(data) = data["errors"].map { |e| e["code"] }

  def bundle
    JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about").tap do |b|
      b["sources"].each { |s| s["retrieved_at"] = Time.now.utc.iso8601 }
    end
  end

  # Records the fixture bundle under a token and returns the "ban" claim.
  def record(token, text: nil)
    b = bundle
    b["claims"].each { |c| c["text"] = "#{c['text']} #{text}" } if text
    b["on_duplicate"] = "create"
    data, err = call_tool("record_investigation", b, token)
    expect(err).to be(false), data.inspect
    Claim.find(data["claims"].find { |c| c["handle"] == "ban" }["id"])
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: password }
  end

  it "revises the person's own claim at once: superseded, pointing forward, links carried (#1)" do
    claim = record(alice_token)
    before_links = claim.evidence_claim_links.effective_at(Contribution.maximum(:seq)).count
    expect(before_links).to be >= 1

    data, err = call_tool("revise_claim", { claim_id: claim.id, text: "Brackenridge restricts cycling on the Market Street mall on December Saturdays.", type: "OBSERVATIONAL", reason: "the passage names one street and one season" }, alice_token)
    expect(err).to be(false), data.inspect
    expect(data).to include("accepted" => true, "status" => "ACCEPTED", "old_claim_id" => claim.id, "carried_links" => before_links)
    new_claim = Claim.find(data["new_claim_id"])
    seq = Contribution.maximum(:seq)
    expect(claim.status_at(seq)).to eq("SUPERSEDED")
    expect(new_claim.supersedes_claim_id).to eq(claim.id)
    expect(new_claim.evidence_claim_links.effective_at(seq).count).to eq(before_links)
    expect(new_claim.evidence_claim_links.first.note).to include("carried from link")
    expect(data.dig("card", "headline")).to be_present

    data, = call_tool("get_claim", { claim_id: claim.id }, nil)
    expect(data.dig("revision", "status")).to eq("SUPERSEDED")
    expect(data.dig("revision", "superseded_by", "claim_id")).to eq(new_claim.id)
    data, = call_tool("fetch", { id: claim.id }, nil)
    expect(data["text"]).to include("Superseded at seq")
    expect(data.dig("metadata", "status")).to eq("SUPERSEDED")

    get "/claims/#{claim.id}"
    expect(response.body).to include("Revised").and include("Superseded at seq").and include(new_claim.canonical_text)
    get "/claims/#{new_claim.id}"
    expect(response.body).to include("Revises")
  end

  it "records a revision of someone else's claim as a proposal that only the entitled principal accepts (#2)" do
    claim = record(alice_token)
    data, err = call_tool("revise_claim", { claim_id: claim.id, text: "Brackenridge restricts cycling on one mall on December Saturdays.", reason: "over-broad" }, bob_token)
    expect(err).to be(false), data.inspect
    expect(data).to include("accepted" => false, "status" => "PENDING")
    expect(data["note"]).to include("proposal")
    proposal = data["contribution_id"]
    expect(claim.status_at(Contribution.maximum(:seq))).to eq("ACTIVE")

    data, err = call_tool("list_proposals", {}, alice_token)
    expect(err).to be(false)
    expect(data["proposals"].map { |x| x["contribution_id"] }).to eq([ proposal ])
    expect(data["proposals"].first).to include("kind" => "SUPERSEDE_CLAIM", "you_may_accept" => true)
    expect(data["proposals"].first["summary"]).to include("Revise to:")

    data, err = call_tool("accept_proposal", { contribution_id: proposal }, bob_token)
    expect(err).to be(true)
    expect(codes(data)).to include("NOT_AUTHORIZED")
    data, err = call_tool("accept_proposal", { contribution_id: proposal }, carol_token)
    expect(err).to be(true)
    expect(codes(data)).to include("NOT_AUTHORIZED")

    data, err = call_tool("accept_proposal", { contribution_id: proposal }, alice_token)
    expect(err).to be(false), data.inspect
    expect(data["carried_links"]).to be >= 1
    seq = Contribution.maximum(:seq)
    expect(claim.status_at(seq)).to eq("SUPERSEDED")
    new_claim = claim.superseded_by_at(seq)
    expect(new_claim.evidence_claim_links.effective_at(seq).count).to be >= 1
    expect(Contribution.find(proposal).current_status).to eq("ACCEPTED")

    # An anonymous principal's claim: anyone named but the proposer may accept.
    data, = call_tool("record_investigation", { "claims" => [ { "handle" => "a", "text" => "An anonymous claim about tides.", "type" => "OBSERVATIONAL" } ] }, nil)
    anon = data["claims"].first["id"]
    data, = call_tool("revise_claim", { claim_id: anon, text: "An anonymous claim about spring tides.", reason: "narrower" }, bob_token)
    expect(data["accepted"]).to be(false)
    data, err = call_tool("accept_proposal", { contribution_id: data["contribution_id"] }, carol_token)
    expect(err).to be(false), data.inspect
    expect(Claim.find(anon).status_at(Contribution.maximum(:seq))).to eq("SUPERSEDED")
  end

  it "merges on acceptance and revises links, own at once and others' as proposals (#3)" do
    claim = record(alice_token)
    twin = record(alice_token, text: "(again)")
    data, = call_tool("merge_claims", { from_claim_id: twin.id, into_claim_id: claim.id, reason: "duplicate" }, bob_token)
    expect(data["accepted"]).to be(false)
    data, err = call_tool("accept_proposal", { contribution_id: data["contribution_id"] }, alice_token)
    expect(err).to be(false), data.inspect
    expect(twin.status_at(Contribution.maximum(:seq))).to eq("MERGED")

    data, = call_tool("merge_claims", { from_claim_id: claim.id, into_claim_id: record(alice_token, text: "(third)").id, reason: "own duplicate" }, alice_token)
    expect(data["accepted"]).to be(true)

    other = record(carol_token, text: "(carol)")
    link = other.evidence_claim_links.effective_at(Contribution.maximum(:seq)).first
    data, err = call_tool("revise_link", { link_id: link.id, direction: "QUALIFY", strength: "WEAK", steps: 2, reason: "a bounded restriction, not a ban" }, carol_token)
    expect(err).to be(false), data.inspect
    expect(data["accepted"]).to be(true)
    seq = Contribution.maximum(:seq)
    expect(link.effective_at?(seq)).to be(false)
    expect(EvidenceClaimLink.find(data["new_link_id"])).to have_attributes(direction: "QUALIFY", relevance_strength: "WEAK", interpretive_steps: 2)

    revised = EvidenceClaimLink.find(data["new_link_id"])
    data, err = call_tool("revise_link", { link_id: revised.id, direction: "CONTRADICT", reason: "stronger reading" }, bob_token)
    expect(err).to be(false), data.inspect
    expect(data["accepted"]).to be(false)
    expect(revised.effective_at?(Contribution.maximum(:seq))).to be(true)
  end

  it "opens a blind task the requester cannot work, without duplicates (#4)" do
    claim = record(alice_token)
    data, err = call_tool("open_task", { claim_id: claim.id, type: "SOURCE_INDEPENDENCE_CHECK" }, bob_token)
    expect(err).to be(false), data.inspect
    expect(data).to include("created" => true, "task_type" => "SOURCE_INDEPENDENCE_CHECK", "status" => "OPEN")
    task_id = data["task_id"]
    data, = call_tool("open_task", { claim_id: claim.id, type: "SOURCE_INDEPENDENCE_CHECK" }, bob_token)
    expect(data).to include("created" => false, "task_id" => task_id)

    data, err = call_tool("open_task", { claim_id: claim.id, type: "EVIDENCE_VERIFICATION" }, bob_token)
    expect(err).to be(true)
    expect(codes(data)).to include("SCHEMA_INVALID")
    data, err = call_tool("open_task", { claim_id: claim.id, type: "QUALIFIER_CHECK" }, nil)
    expect(err).to be(true)
    expect(codes(data)).to include("TOKEN_INVALID")

    data, = call_tool("next_task", { claim_id: claim.id, types: [ "SOURCE_INDEPENDENCE_CHECK" ] }, bob_token)
    expect(data["available"]).to be(false)
    data, = call_tool("next_task", { claim_id: claim.id, types: [ "SOURCE_INDEPENDENCE_CHECK" ] }, alice_token)
    expect(data["available"]).to be(false)
    data, = call_tool("next_task", { claim_id: claim.id, types: [ "SOURCE_INDEPENDENCE_CHECK" ] }, carol_token)
    expect(data["available"]).to be(true)
    expect(data["task_id"]).to eq(task_id)
  end

  it "lets the claim's principal accept on the page and refuses the proposer; replay is unchanged (#5)" do
    claim = record(alice_token)
    data, = call_tool("revise_claim", { claim_id: claim.id, text: "Brackenridge restricts cycling on one mall.", reason: "narrower" }, bob_token)
    proposal = data["contribution_id"]

    sign_in(bob)
    get "/claims/#{claim.id}"
    expect(response.body).to include("Proposed corrections").and include("awaits the claim")
    expect(response.body).not_to include("Accept</button>")
    post "/claims/#{claim.id}/accept", params: { contribution_id: proposal }
    follow_redirect!
    expect(response.body).to include("only the principal")
    expect(Contribution.find(proposal).current_status).to eq("PENDING")
    delete session_path

    sign_in(alice)
    get "/claims/#{claim.id}"
    expect(response.body).to include("Accept")
    post "/claims/#{claim.id}/accept", params: { contribution_id: proposal }
    follow_redirect!
    expect(response.body).to include("Accepted as a signed contribution")
    expect(Contribution.find(proposal).current_status).to eq("ACCEPTED")
    expect(claim.status_at(Contribution.maximum(:seq))).to eq("SUPERSEDED")

    before = Ledger::TableDigest.projections
    Ledger::Replay.call
    expect(Ledger::TableDigest.projections).to eq(before)
  end
end
