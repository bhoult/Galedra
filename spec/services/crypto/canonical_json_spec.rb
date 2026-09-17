require "rails_helper"

RSpec.describe Crypto::CanonicalJson do
  vectors = JSON.parse(File.read(Rails.root.join("spec/fixtures/canonical_json_vectors.json")))

  vectors["rfc8785"].each do |vector|
    it "serializes #{vector['name']} exactly as the RFC specifies" do
      canonical = described_class.serialize(vector["input"])
      expect(canonical).to eq(vector["expected"])
      expect(Crypto::Hashing.bytes(canonical)).to eq("sha256:#{vector['sha256']}")
    end
  end

  vectors["project"].each do |vector|
    it "canonicalizes #{vector['name']}" do
      expect(described_class.call(vector["input"])).to eq(vector["expected"])
    end

    it "hashes #{vector['name']} to the published digest" do
      expect(Crypto::Hashing.json(vector["input"])).to eq("sha256:#{vector['sha256']}")
    end
  end

  it "treats symbol and string keys identically" do
    expect(described_class.call({ b: 1, a: [ 1, "x" ] })).to eq('{"a":[1,"x"],"b":1}')
  end

  it "rejects floats anywhere in the structure" do
    expect { described_class.call({ "ops" => [ { "weight" => 0.5 } ] }) }
      .to raise_error(ArgumentError, /float at \$\.ops\[0\]\.weight/)
  end
end
