require "rails_helper"

RSpec.describe "Takedown (spec 02 §5; 07 Phase 2 #8)", type: :request do
  let(:curator) { register_key(display_name: "Curator").first }
  let(:moderator) { register_moderator.first }

  it "removes the bytes, keeps the chain verifiable with redactions, and replays the redacted projection" do
    source = create_source(curator, title: "Unlicensed scan", content: "Copyrighted text reproduced without permission.")
    location = create_location(curator, source, start: 0, finish: 16)
    claim = create_claim(curator, "The scan says copyrighted text.", qualifiers: { "edition" => "2nd" })
    evidence = create_evidence(curator, location, statement: "Reproduces the passage.")
    link_evidence(curator, evidence, claim)
    target = source.contribution

    get "/api/v1/contributions/#{target.id}/redaction_manifest"
    manifest = response.parsed_body["redaction_manifest"]
    expect(manifest.map { |m| m["table"] }).to eq([ "sources" ])
    expect(manifest.first["removed"]).to include("content", "title")
    expect(manifest.first["retained"]).to include("source_type" => "PRIMARY_TEXT", "content_hash" => source.content_hash)

    td = takedown(moderator, target, legal_basis: "DMCA notice 2026-09-17")
    expect(target.reload.payload).to be_nil
    expect(target.envelope).to be_nil
    expect(target.redacted_by_seq).to eq(td.seq)
    expect(target.entry_hash).to be_present
    expect(source.reload).to have_attributes(title: nil, content: nil, redacted_by_seq: td.seq, content_hash: source.content_hash)
    expect(source.source_type).to eq("PRIMARY_TEXT")

    result = Ledger::Verify.call
    expect(result.status).to eq("CHAIN_VERIFIED_WITH_REDACTIONS")
    expect(result.redacted_seqs).to eq([ target.seq ])
    expect(Ledger::Verify.entry(target)).to include(client_signature_ok: false, server_signature_ok: true, chain_ok: true)

    get "/api/v1/contributions/#{target.id}"
    expect(response.parsed_body["contribution"]).to include("redacted_by_seq" => td.seq, "envelope" => nil, "entry_hash" => target.entry_hash)
    get "/api/v1/moderation"
    entry = response.parsed_body["entries"].find { |e| e["action"] == "TAKEDOWN" }
    expect(entry).to include("target_id" => target.id, "legal_basis" => "DMCA notice 2026-09-17", "moderator_key_id" => moderator.key_id, "reason" => "LEGAL_REMOVAL")
    expect(response.body).not_to include("Copyrighted text")

    before = Ledger::TableDigest.projections
    replay = Ledger::Replay.call
    expect(replay.applied).to eq(Contribution.count)
    expect(Ledger::TableDigest.projections).to eq(before)
    expect(Source.find(source.id)).to have_attributes(title: nil, content: nil, redacted_by_seq: td.seq)
    expect(EvidenceItem.find(evidence.id).statement).to eq("Reproduces the passage.")
  end

  it "takes down a claim while keeping its type and later history usable" do
    reviewer, = register_key
    claim = create_claim(curator, "Defamatory sentence about a private person.", type: "OBSERVATIONAL", qualifiers: { "location" => "town" })
    setting = append(action_type: "SET_TRUTH_EVALUABLE", key_pair: reviewer, payload: { "claim_id" => claim.id, "truth_evaluable" => false, "not_evaluable_reason" => "UNTESTABLE_CURRENT_METHODS" })
    accept(curator, setting.contribution)
    td = takedown(moderator, claim.contribution)

    expect(claim.reload).to have_attributes(canonical_text: nil, qualifiers: {}, claim_type: "OBSERVATIONAL", redacted_by_seq: td.seq, truth_evaluable: false)
    get "/api/v1/claims/#{claim.id}"
    expect(response.parsed_body["claim"]).to include("text" => nil, "redacted" => true, "type" => "OBSERVATIONAL")
    expect(response.body).not_to include("Defamatory")

    before = Ledger::TableDigest.projections
    Ledger::Replay.call
    expect(Ledger::TableDigest.projections).to eq(before)
    expect(claim.reload.evaluability_at(Contribution.maximum(:seq))).to eq([ false, "UNTESTABLE_CURRENT_METHODS" ])
  end

  it "rejects takedowns by non-moderators, of control contributions, twice, or with a stale manifest" do
    claim = create_claim(curator, "Something.")
    expect_rejected("NOT_AUTHORIZED") { takedown(curator, claim.contribution) }
    expect_rejected("NOT_REDACTABLE") { takedown(moderator, Contribution.find_by!(seq: 0)) }

    manifest = Ledger::Redaction.manifest_for(claim.contribution)
    manifest.first["retained"]["claim_type"] = "CAUSAL"
    expect_rejected("MANIFEST_MISMATCH") do
      append(action_type: "TAKEDOWN", key_pair: moderator, payload: { "contribution_id" => claim.contribution_id, "legal_basis" => "x", "requested_at" => "2026-09-17", "redaction_manifest" => manifest })
    end
    manifest = Ledger::Redaction.manifest_for(claim.contribution)
    manifest.first["removed"] = [ "claim_type" ]
    expect_rejected("MANIFEST_MISMATCH") do
      append(action_type: "TAKEDOWN", key_pair: moderator, payload: { "contribution_id" => claim.contribution_id, "legal_basis" => "x", "requested_at" => "2026-09-17", "redaction_manifest" => manifest })
    end
    expect_rejected("MANIFEST_MISMATCH") do
      append(action_type: "TAKEDOWN", key_pair: moderator, payload: { "contribution_id" => claim.contribution_id, "legal_basis" => "x", "requested_at" => "2026-09-17", "redaction_manifest" => [] })
    end

    takedown(moderator, claim.contribution)
    expect_rejected("ALREADY_REDACTED") { takedown(moderator, claim.contribution, legal_basis: "again") }
    expect(claim.reload.canonical_text).to be_nil
  end

  it "detects bytes removed without a takedown" do
    claim = create_claim(curator, "Quietly deleted.")
    as_owner { Contribution.where(id: claim.contribution_id).update_all(payload: nil, envelope: nil, redacted_by_seq: 999_999) }
    result = Ledger::Verify.call
    expect(result.status).to eq("CHAIN_BROKEN")
    expect(result.first_break).to include(seq: claim.contribution.seq)
    expect(result.first_break[:reason]).to match(/without a matching TAKEDOWN/)
  end
end
