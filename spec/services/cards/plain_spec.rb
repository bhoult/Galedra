require "rails_helper"

RSpec.describe Cards::Plain do
  before { release_models }

  let(:curator) { register_key(display_name: "Curator").first }
  let(:model) { Scoring::Registry.default_model }
  let(:long) { (%w[word] * 30).join(" ") + "." }

  def plain_for(claim) = described_class.call(claim, Contribution.maximum(:seq), model, Scoring::Score.call(claim, Contribution.maximum(:seq), model))

  def evidence(statement)
    source = create_source(curator, content: "Motion 14 carried. #{long}")
    create_evidence(curator, create_location(curator, source, start: 0, finish: 18), statement: statement)
  end

  it "offers nothing for a claim that holds up, even with a qualifier attached" do
    claim = create_claim(curator, "Motion 14 carried.")
    link_evidence(curator, evidence("The minutes record that Motion 14 carried."), claim)
    link_evidence(curator, evidence(long), claim, direction: "QUALIFY")
    expect(plain_for(claim)).to eq(headline: "Checks out so far.", say_instead: nil)
  end

  it "skips a sentence over #{described_class::MAX_WORDS} words rather than cutting it short, and prefers the claim a qualifier points to" do
    claim = create_claim(curator, "The council banned bicycles.")
    link_evidence(curator, evidence(long), claim, direction: "CONTRADICT")
    expect(plain_for(claim)).to eq(headline: "The evidence goes against this.", say_instead: nil)

    narrow = create_claim(curator, "The council banned bicycles on Market Street on Saturdays.")
    qualifier = evidence(long)
    link_evidence(curator, qualifier, narrow)
    link_evidence(curator, qualifier, claim, direction: "QUALIFY")
    expect(plain_for(claim)[:say_instead]).to eq("The council banned bicycles on Market Street on Saturdays.")

    short = evidence("The ban covers Market Street on Saturdays only.")
    link_evidence(curator, short, claim, direction: "CONTRADICT")
    # Under ledger-default@0.1.0 this preferred the short contradiction; under
    # 0.2.0 it prefers the narrower claim, which is the order this method's own
    # comment describes ("a narrower claim that holds up" before "the strongest
    # counted contradiction"). Both sentences are true of the claim and neither
    # is invented, so nothing here is wrong for a reader — but the mechanism
    # behind the change was not traced, and the precedence deserves a look on
    # its own rather than being settled by whichever model happens to be default.
    expect(plain_for(claim)[:say_instead]).to eq("The council banned bicycles on Market Street on Saturdays.")
  end
end
