require "rails_helper"

RSpec.describe Crypto::Custody do
  let(:user) { create(:user) }

  describe ".create_server_custodied" do
    it "registers the key through the log with SERVER custody and stores the private key encrypted" do
      contributor = described_class.create_server_custodied(user: user, display_name: "Curator")

      expect(contributor).to be_persisted
      expect(contributor.kind).to eq(Contributor::HUMAN)
      expect(contributor.display_name).to eq("Curator")
      expect(contributor).to be_server_custodied
      expect(contributor.custodied_key.user).to eq(user)

      registration = Contribution.find_by!(signer_key_id: contributor.key_id, action_type: "REGISTER_KEY")
      expect(registration.custody).to eq(described_class::SERVER)
      expect(registration.contributor_id).to be_nil

      ciphertext = CustodiedKey.connection.select_value(
        "SELECT encrypted_private_key FROM custodied_keys WHERE contributor_id = '#{contributor.id}'"
      )
      expect(ciphertext).not_to include(contributor.custodied_key.encrypted_private_key)
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

    it "refuses for a user with no server-custodied key" do
      expect { described_class.signer_for(user) }.to raise_error(described_class::NoServerKey)
    end
  end
end
