require "rails_helper"

RSpec.describe Crypto::Custody do
  let(:user) { create(:user) }

  describe ".create_server_custodied" do
    it "creates a HUMAN contributor whose private key is stored encrypted" do
      contributor = described_class.create_server_custodied(user: user, display_name: "Curator")

      expect(contributor).to be_persisted
      expect(contributor.kind).to eq(Contributor::HUMAN)
      expect(contributor.user).to eq(user)
      expect(contributor).to be_server_custodied
      expect(contributor.key_id).to eq(Crypto::Ed25519.key_id(contributor.public_key))

      ciphertext = Contributor.connection.select_value(
        "SELECT encrypted_private_key FROM contributors WHERE id = '#{contributor.id}'"
      )
      expect(ciphertext).not_to include(contributor.encrypted_private_key)
      expect(ciphertext).to include('"p":')
    end
  end

  describe ".signer_for" do
    it "unlocks the key for the authenticated user and signs verifiably" do
      contributor = described_class.create_server_custodied(user: user)
      signer = described_class.signer_for(user)

      signature = signer.sign("bytes")
      expect(signer.key_id).to eq(contributor.key_id)
      expect(Crypto::Ed25519.verify(contributor.public_key, signature, "bytes")).to be(true)
    end

    it "refuses without an authenticated user" do
      expect { described_class.signer_for(nil) }.to raise_error(described_class::NotAuthenticated)
    end

    it "refuses for a user with only self-custodied keys" do
      create(:contributor, user: user)
      expect { described_class.signer_for(user) }.to raise_error(described_class::NoServerKey)
    end
  end
end
