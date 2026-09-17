require "rails_helper"

RSpec.describe Crypto::Hashing do
  it "prefixes raw-byte digests with sha256:" do
    expect(described_class.bytes("abc"))
      .to eq("sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  end

  it "hashes the canonical form, so key order does not matter" do
    expect(described_class.json({ "b" => 1, "a" => 2 })).to eq(described_class.json({ "a" => 2, "b" => 1 }))
  end

  it "changes when any payload byte changes" do
    expect(described_class.json({ "note" => "same figure" })).not_to eq(described_class.json({ "note" => "same figurf" }))
  end

  it "validates the hash format" do
    expect(described_class.valid?("sha256:#{'a' * 64}")).to be(true)
    expect(described_class.valid?("sha256:#{'a' * 63}")).to be(false)
    expect(described_class.valid?("sha1:#{'a' * 64}")).to be(false)
  end
end
