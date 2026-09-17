require "rails_helper"

RSpec.describe Crypto::SystemKey do
  let(:vector) { JSON.parse(File.read(Rails.root.join("spec/fixtures/canonical_json_vectors.json")))["ed25519"].first }

  it "loads the key pair from the environment (RFC 8032 test vector 1 in tests)" do
    expect(described_class.configured?).to be(true)
    expect(described_class.public_key).to eq(vector["public_key"])
    expect(described_class.key_id).to eq(vector["key_id"])
  end

  it "raises when the pinned public key does not match the private key" do
    other = Crypto::Ed25519::KeyPair.generate
    with_env(described_class::PUBLIC_ENV => other.public_key) do
      expect { described_class.key_pair }.to raise_error(described_class::Mismatch)
    end
  end

  it "reports missing configuration instead of guessing" do
    with_env(described_class::PRIVATE_ENV => nil) do
      expect(described_class.configured?).to be(false)
      expect { described_class.key_pair }.to raise_error(described_class::Missing, /ledger:keygen/)
    end
  end

  it "is never stored as a custodied key" do
    system = Contributor.find_by!(kind: Contributor::SYSTEM)
    custodied = CustodiedKey.new(contributor: system, user: create(:user), encrypted_private_key: "anything")
    expect(custodied).not_to be_valid
    expect(custodied.errors[:contributor]).to be_present
    expect(CustodiedKey.joins(:contributor).where(contributors: { kind: Contributor::SYSTEM })).to be_empty
  end
end
