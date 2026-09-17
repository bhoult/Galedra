require "rails_helper"

RSpec.describe Ledger::Verify do
  before do
    pair, = register_key
    create_claim(pair, "a")
    create_claim(pair, "b")
  end

  it "verifies an intact chain from the log alone" do
    result = described_class.call
    expect(result.status).to eq(described_class::CHAIN_VERIFIED)
    expect(result.checked).to eq(Contribution.count)
    expect(result.head_seq).to eq(Contribution.maximum(:seq))
    expect(result.head_hash).to eq(Contribution.in_order.last.entry_hash)
  end

  it "detects a corrupted payload and reports its seq (07 Phase 1 #6)" do
    target = Contribution.where(action_type: "CREATE_CLAIM").in_order.last
    as_owner { Contribution.where(id: target.id).update_all("payload = jsonb_set(payload, '{canonical_text}', '\"forged\"')") }

    result = described_class.call
    expect(result.status).to eq(described_class::CHAIN_BROKEN)
    expect(result.first_break).to eq(seq: target.seq, reason: "payload_hash does not match the stored payload")
    expect(described_class.entry(target.reload)[:chain_ok]).to be(false)
  end

  it "detects a rewritten chain hash" do
    target = Contribution.in_order.last
    as_owner { Contribution.where(id: target.id).update_all(entry_hash: "sha256:#{'f' * 64}") }
    result = described_class.call
    expect(result.first_break[:seq]).to eq(target.seq)
    expect(result.first_break[:reason]).to eq("entry_hash does not recompute")
  end

  it "detects a broken link between entries" do
    target = Contribution.in_order.last
    as_owner { Contribution.where(id: target.id).update_all(prev_hash: "sha256:#{'e' * 64}") }
    expect(described_class.call.first_break).to include(seq: target.seq, reason: "prev_hash does not match the previous entry")
  end
end
