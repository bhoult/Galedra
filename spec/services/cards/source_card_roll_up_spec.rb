require "rails_helper"

# A source whose claims were all CONTRADICTED, or all LEANS_SUPPORTED, added
# nil to a number in the summary and its page answered 500 (2026-09-29).
RSpec.describe Cards::SourceCard do
  it "summarises a source with only one of each paired state" do
    expect(described_class.roll_up([ { assessment_state: "CONTRADICTED" } ])).to include("1 leans contradicted or contradicted")
    expect(described_class.roll_up([ { assessment_state: "LEANS_SUPPORTED" } ])).to include("1 supported or leans supported")
  end
end
