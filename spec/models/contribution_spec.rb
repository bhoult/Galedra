require "rails_helper"

RSpec.describe Contribution, type: :model do
  let(:contribution) { register_key.then { |pair, _| Contribution.find_by!(signer_key_id: pair.key_id) } }

  it "gets a UUIDv7 id at append time" do
    expect(contribution.id).to match(/\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/)
  end

  it "allows only the cached status column to change" do
    expect(contribution.update(current_status: Contribution::CHALLENGED)).to be(true)
    expect { contribution.update!(payload: {}) }.to raise_error(Ledger::AppendOnlyViolation, /payload/)
    expect { contribution.update!(entry_hash: "sha256:#{'0' * 64}") }.to raise_error(Ledger::AppendOnlyViolation)
  end

  it "is never destroyed" do
    expect { contribution.destroy }.to raise_error(Ledger::AppendOnlyViolation)
  end

  it "renders received_at with microseconds in UTC" do
    expect(contribution.received_at_rfc3339).to match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z\z/)
  end
end
