require "rails_helper"

RSpec.describe "Claim identity (spec 02 §3.3; 07 Phase 2 #7)" do
  let(:curator) { register_key(display_name: "Curator").first }

  it "lets near-identical claims coexist and only suggests them as duplicates" do
    other, = register_key
    broad = create_claim(curator, "62% of remote workers report higher productivity.", type: "QUANTITATIVE")
    narrow = create_claim(curator, "62% of 400 remote employees of Acme customers surveyed by Acme in 2026 reported higher productivity.", type: "QUANTITATIVE")
    twin = create_claim(other, "62% of remote workers report higher productivity.", type: "QUANTITATIVE")
    # The same signer resubmitting an identical payload gets the original back (idempotency, 02 §3.1).
    expect(create_claim(curator, broad.canonical_text, type: "QUANTITATIVE")).to eq(broad)

    expect(twin.id).not_to eq(broad.id)
    expect(Claim.where(canonical_text: broad.canonical_text).count).to eq(2)
    suggestions = Claims::Duplicates.candidates(broad.canonical_text, exclude_id: broad.id)
    expect(suggestions.map(&:id)).to include(twin.id, narrow.id)
    expect(suggestions.first.similarity).to be > 0.9
    expect(ClaimMerge.count).to eq(0)
  end

  it "merges only by an explicit, accepted MERGE_CLAIMS and reverses it by INVALIDATE" do
    reviewer, = register_key
    broad = create_claim(curator, "62% of remote workers report higher productivity.", type: "QUANTITATIVE")
    twin = create_claim(reviewer, "62 percent of remote workers report higher productivity.", type: "QUANTITATIVE")
    source = create_source(curator)
    evidence = create_evidence(curator, create_location(curator, source))

    merge = append(action_type: "MERGE_CLAIMS", key_pair: curator, payload: { "from_claim_id" => twin.id, "into_claim_id" => broad.id, "reason" => "same proposition" })
    expect(merge.acceptance).to be_nil
    expect(twin.reload.status).to eq("ACTIVE")
    expect(link_evidence(curator, evidence, twin)).to be_persisted

    accepted = accept(reviewer, merge.contribution)
    expect(twin.reload.status).to eq("MERGED")
    expect(twin.merged_into_id).to eq(broad.id)
    expect(twin.status_at(accepted.seq - 1)).to eq("ACTIVE")
    expect(twin.status_at(accepted.seq)).to eq("MERGED")
    expect_rejected("CLAIM_NOT_CURRENT") { link_evidence(curator, evidence, twin, note: "after merge") }

    reversed = invalidate(curator, merge.contribution, reason: "different populations")
    expect(twin.reload.status).to eq("ACTIVE")
    expect(twin.merged_into_id).to be_nil
    expect(twin.status_at(reversed.seq - 1)).to eq("MERGED")
    expect(twin.status_at(reversed.seq)).to eq("ACTIVE")
    expect(link_evidence(curator, evidence, twin, direction: "QUALIFY")).to be_persisted
  end

  it "auto-accepts a merge of one's own claims" do
    a = create_claim(curator, "Alpha.")
    b = create_claim(curator, "Alpha, restated.")
    merge = append(action_type: "MERGE_CLAIMS", key_pair: curator, payload: { "from_claim_id" => b.id, "into_claim_id" => a.id })
    expect(merge.acceptance).to be_present
    expect(b.reload.status).to eq("MERGED")
    expect_rejected("CLAIM_NOT_CURRENT") { append(action_type: "MERGE_CLAIMS", key_pair: curator, payload: { "from_claim_id" => b.id, "into_claim_id" => a.id, "reason" => "again" }) }
  end

  it "supersedes a claim with a corrected one and derives the old status from the new row's window" do
    claim = create_claim(curator, "The survey covered remote workers.", type: "TEXTUAL")
    result = append(action_type: "SUPERSEDE_CLAIM", key_pair: curator,
                    payload: claim_payload("The survey covered 400 remote employees of Acme customers.", reason: "population omitted").merge("claim_id" => claim.id))
    replacement = Claim.find(Ledger::Ids.derive(result.contribution.id, "claim"))
    expect(replacement.supersedes_claim_id).to eq(claim.id)
    expect(claim.reload.status).to eq("SUPERSEDED")
    expect(claim.superseded_by_id).to eq(replacement.id)
    expect(claim.status_at(replacement.accepted_seq - 1)).to eq("ACTIVE")
    expect_rejected("CLAIM_NOT_CURRENT") { create_edge(curator, claim, replacement) }

    invalidate(curator, result.contribution)
    expect(claim.reload.status).to eq("ACTIVE")
    expect(replacement.reload.status).to eq("RETIRED")
  end
end
