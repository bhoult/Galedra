require "rails_helper"

RSpec.describe "Quarantine (spec 05 §13)", type: :request do
  let(:curator) { register_key(display_name: "Curator").first }
  let(:moderator) { register_moderator.first }

  it "withholds a quarantined claim's text everywhere but leaves a public stub at its URL" do
    claim = create_claim(curator, "Jane Doe of 12 Example Street owes money.", type: "OBSERVATIONAL")
    source = create_source(curator, title: "Diary", content: "A neighbour owes money to everyone.")
    evidence = create_evidence(curator, create_location(curator, source), statement: "The diary mentions a debt.")
    link_evidence(curator, evidence, claim)
    before = Contribution.maximum(:seq)

    q = quarantine(moderator, claim, reason: "PRIVATE_INDIVIDUAL", note: "identifiable person")
    expect(claim.reload.status).to eq("QUARANTINED")
    expect(claim.status_at(before)).to eq("ACTIVE")
    expect(claim.status_at(q.created_seq)).to eq("QUARANTINED")

    get "/api/v1/claims/#{claim.id}"
    expect(response).to have_http_status(:ok)
    body = response.parsed_body["claim"]
    expect(body["text"]).to be_nil
    expect(body["status"]).to eq("QUARANTINED")
    expect(body["quarantine"]).to include("moderator_key_id" => moderator.key_id, "reason" => "PRIVATE_INDIVIDUAL", "appeal_status" => "OPEN", "appeal_path" => "/api/v1/moderation")
    expect(response.body).not_to include("Jane Doe")

    get "/api/v1/claims/#{claim.id}", params: { snapshot_seq: before }
    expect(response.parsed_body["claim"]["text"]).to be_nil

    get "/api/v1/claims/#{claim.id}/evidence"
    expect(response.parsed_body["counted"]).to eq([])
    expect(response.parsed_body["quarantined"]).to be(true)

    get "/api/v1/claims", params: { q: "Jane" }
    expect(response.parsed_body["claims"]).to eq([])
    get "/api/v1/log", params: { after_seq: before - 20 }
    entry = response.parsed_body["entries"].find { |e| e["id"] == claim.contribution_id }
    expect(entry["envelope"]).to be_nil
    expect(entry["withheld"]).to include("reason" => "QUARANTINE")
    expect(entry["entry_hash"]).to eq(claim.contribution.entry_hash)
    expect(response.body).not_to include("Jane Doe")

    get "/api/v1/moderation"
    log_entry = response.parsed_body["entries"].find { |e| e["action"] == "QUARANTINE" && e["target_id"] == claim.id }
    expect(log_entry).to include("moderator_key_id" => moderator.key_id, "reason" => "PRIVATE_INDIVIDUAL", "appeal_status" => "OPEN")

    expect_rejected("ALREADY_QUARANTINED") { quarantine(moderator, claim) }
    release = append(action_type: "RELEASE_QUARANTINE", key_pair: moderator, payload: { "quarantine_id" => q.id, "note" => "appeal upheld" }).contribution
    expect(claim.reload.status).to eq("ACTIVE")
    expect(claim.status_at(release.seq - 1)).to eq("QUARANTINED")
    get "/api/v1/claims/#{claim.id}"
    expect(response.parsed_body["claim"]["text"]).to eq("Jane Doe of 12 Example Street owes money.")
    get "/api/v1/moderation"
    expect(response.parsed_body["entries"].map { |e| e["action"] }).to include("QUARANTINE", "RELEASE_QUARANTINE")
    expect(response.parsed_body["entries"].find { |e| e["action"] == "QUARANTINE" }["appeal_status"]).to eq("RELEASED")
  end

  it "withholds a quarantined source's content, excerpts, and evidence statements" do
    source = create_source(curator, title: "Leaked file", content: "Home address: 12 Example Street.")
    location = create_location(curator, source)
    evidence = create_evidence(curator, location, statement: "Lists a home address.")
    quarantine(moderator, source, reason: "PERSONAL_DATA")

    get "/api/v1/sources/#{source.id}"
    expect(response.parsed_body["source"]).to include("title" => nil, "content" => nil, "quarantined" => true)
    get "/api/v1/sources/#{source.id}/locations"
    expect(response.parsed_body["locations"].first).to include("excerpt" => nil, "withheld" => true)
    get "/api/v1/evidence/#{evidence.id}"
    expect(response.parsed_body["evidence"]).to include("statement" => nil, "withheld" => true)
    expect(response.body).not_to include("Example Street")
    get "/api/v1/log", params: { after_seq: source.created_seq - 1, limit: 10 }
    expect(response.body).not_to include("Example Street")
  end

  it "rejects reasons outside the closed list, non-moderators, and unknown targets" do
    claim = create_claim(curator, "A claim.")
    expect_rejected("SCHEMA_INVALID") { quarantine(moderator, claim, reason: "I_DISAGREE") }
    expect_rejected("NOT_AUTHORIZED") { quarantine(curator, claim) }
    expect_rejected("TARGET_UNKNOWN") { quarantine(moderator, Claim.new(id: SecureRandom.uuid)) }
    expect(Quarantine.count).to eq(0)
    get "/api/v1/meta"
    expect(response.parsed_body["moderator_key_ids"]).to include(moderator.key_id)
  end

  it "lets moderators suspend keys and invalidate contributions, and lists suspensions" do
    victim_pair, victim = register_key
    claim = create_claim(victim_pair, "Spam claim.")
    invalidate(moderator, claim.contribution, reason: "SPAM")
    expect(claim.reload.status).to eq("RETIRED")
    append(action_type: "REVOKE_KEY", key_pair: moderator, payload: { "key_id" => victim.key_id, "reason" => "spam" })
    expect(victim.reload).to be_revoked

    get "/api/v1/moderation"
    suspension = response.parsed_body["entries"].find { |e| e["action"] == "SUSPENSION" }
    expect(suspension).to include("target_type" => "KEY", "target_id" => victim.key_id, "moderator_key_id" => moderator.key_id)
  end

  it "requires the private-individual affirmation on every claim" do
    expect_rejected("PRIVATE_INDIVIDUAL_AFFIRMATION_REQUIRED") do
      append(action_type: "CREATE_CLAIM", key_pair: curator, payload: { "canonical_text" => "x", "claim_type" => "TEXTUAL" })
    end
    expect_rejected("PRIVATE_INDIVIDUAL_AFFIRMATION_REQUIRED") do
      append(action_type: "CREATE_CLAIM", key_pair: curator, payload: { "canonical_text" => "x", "claim_type" => "TEXTUAL", "affirms_not_private_individual" => false })
    end
  end
end
