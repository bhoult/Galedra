require "rails_helper"

RSpec.describe Crypto::Ed25519 do
  vectors = JSON.parse(File.read(Rails.root.join("spec/fixtures/canonical_json_vectors.json")))["ed25519"]

  vectors.each do |vector|
    context vector["name"] do
      let(:pair) { described_class::KeyPair.from_private_key(vector["private_key"]) }
      let(:message) { [ vector["message_hex"] ].pack("H*") }

      it "derives the published public key and key id" do
        expect(pair.public_key).to eq(vector["public_key"])
        expect(pair.key_id).to eq(vector["key_id"])
        expect(described_class.key_id(vector["public_key"])).to eq(vector["key_id"])
      end

      it "produces the published signature (Ed25519 is deterministic)" do
        expect(pair.sign(message)).to eq(vector["signature"])
      end

      it "verifies the published signature" do
        expect(described_class.verify(vector["public_key"], vector["signature"], message)).to be(true)
      end
    end
  end

  describe "tampering" do
    let(:pair) { described_class::KeyPair.generate }
    let(:vector) { JSON.parse(File.read(Rails.root.join("spec/fixtures/canonical_json_vectors.json")))["project"].first }
    let(:canonical) { Crypto::CanonicalJson.call(vector["input"]) }
    let(:signature) { pair.sign(canonical) }

    it "verifies the untouched canonical envelope" do
      expect(described_class.verify(pair.public_key, signature, canonical)).to be(true)
    end

    it "fails when one byte of the signed bytes changes" do
      tampered = canonical.dup
      tampered[tampered.index("CONFIRMED") + 1] = "0"
      expect(described_class.verify(pair.public_key, signature, tampered)).to be(false)
    end

    it "fails when the payload changes before canonicalization" do
      changed = vector["input"].deep_dup
      changed["payload"]["ops"][0]["interpretive_steps"] = 1
      expect(described_class.verify(pair.public_key, signature, Crypto::CanonicalJson.call(changed))).to be(false)
    end

    it "fails when the signature or key is altered or malformed" do
      other = described_class::KeyPair.generate
      expect(described_class.verify(other.public_key, signature, canonical)).to be(false)
      flipped = (signature[0] == "A" ? "B" : "A") + signature[1..]
      expect(described_class.verify(pair.public_key, flipped, canonical)).to be(false)
      expect(described_class.verify(pair.public_key, "not-a-signature", canonical)).to be(false)
      expect(described_class.verify("short", signature, canonical)).to be(false)
    end
  end

  it "round-trips a generated private key" do
    pair = described_class::KeyPair.generate
    restored = described_class::KeyPair.from_private_key(pair.private_key)
    expect(restored.public_key).to eq(pair.public_key)
    expect(pair.key_id).to match(described_class::KEY_ID_FORMAT)
  end
end
