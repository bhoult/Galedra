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

  it "is never stored in the contributors table" do
    contributor = Contributor.new(kind: Contributor::SYSTEM, public_key: described_class.public_key,
                                  key_id: described_class.key_id, encrypted_private_key: "anything")
    expect(contributor).not_to be_valid
    expect(contributor.errors[:encrypted_private_key]).to be_present
    expect(Contributor.where(kind: Contributor::SYSTEM).where.not(encrypted_private_key: nil)).to be_empty
  end

  def with_env(overrides)
    saved = overrides.keys.to_h { |k| [ k, ENV[k] ] }
    overrides.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
