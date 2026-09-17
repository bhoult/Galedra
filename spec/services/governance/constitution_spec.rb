require "rails_helper"

RSpec.describe Governance::Constitution do
  subject(:constitution) { described_class.new }

  let(:spec_copy) do
    Rails.root.join("docs/epistemic-ledger-poc-spec-v4/epistemic-ledger-poc/12-constitution.md")
  end

  it "is a byte-identical copy of the spec's 12-constitution.md" do
    expect(File.binread(described_class::PATH)).to eq(File.binread(spec_copy))
  end

  it "reports the adopted version" do
    expect(constitution.version).to eq("1.0.0")
  end

  it "hashes the file bytes with a sha256: prefix" do
    expected = "sha256:#{Digest::SHA256.hexdigest(File.binread(spec_copy))}"
    expect(constitution.digest).to eq(expected)
  end
end
