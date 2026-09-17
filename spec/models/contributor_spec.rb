require "rails_helper"

RSpec.describe Contributor, type: :model do
  it "is a projection: writable only inside Ledger::Apply" do
    _, contributor = register_key
    expect { contributor.update!(display_name: "renamed") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { contributor.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { build(:contributor).save }.to raise_error(ActiveRecord::ReadOnlyRecord)
    Ledger.applying { expect(contributor.update(display_name: "renamed")).to be(true) }
  end

  it "requires the key id to match the public key" do
    contributor = build(:contributor, key_id: "ed25519:#{'0' * 64}")
    expect(contributor).not_to be_valid
    expect(contributor.errors[:key_id]).to include("does not match the public key")
  end

  it "enforces unique key ids" do
    existing = create(:contributor)
    duplicate = build(:contributor, key_pair: nil, public_key: existing.public_key, key_id: existing.key_id)
    expect(duplicate).not_to be_valid
  end

  it "restricts kind and identity tier to the closed lists" do
    expect(build(:contributor, kind: "ROBOT")).not_to be_valid
    expect(build(:contributor, identity_tier: "UNSIGNED")).not_to be_valid
  end

  it "defaults to the pseudonymous tier" do
    expect(described_class.new.identity_tier).to eq("PSEUDONYMOUS")
  end
end
