require "rails_helper"

RSpec.describe Ledger::Ids do
  it "derives the same UUID for the same inputs and a different one otherwise" do
    a = described_class.derive("0192", "contributor")
    expect(a).to eq(described_class.derive("0192", "contributor"))
    expect(a).not_to eq(described_class.derive("0192", "delegation"))
    expect(a).to match(/\A\h{8}-\h{4}-8\h{3}-[89ab]\h{3}-\h{12}\z/)
  end
end
