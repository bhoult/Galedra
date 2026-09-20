require "rails_helper"

RSpec.describe Cards::Plain do
  before { release_models }

  let(:curator) { register_key(display_name: "Curator").first }
  let(:model) { Scoring::Registry.default_model }
  let(:long) { (%w[word] * 30).join(" ") + "." }

  def plain_for(claim) = described_class.call(claim, Contribution.maximum(:seq), model, Scoring::Score.call(claim, Contribution.maximum(:seq), model))

  # `origin` decides whether two readings share a passage. The payloads are
  # byte-identical for a given origin, so the log's idempotency returns the same
  # source and the same location — which is what makes two readings of it
  # dependent under ledger-default@0.2.0. Left as the default because the tests
  # below depend on it; pass a different origin when independence is the point.
  def evidence(statement, origin: "Motion 14 carried.")
    source = create_source(curator, content: "#{origin} #{long}")
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
    # Traced 2026-09-20. The precedence did not change between models; which
    # links carry weight did. Both contradictions here are readings of ONE
    # passage — every `evidence` call above builds the same source payload, so
    # the log returns one source and one location — and 0.2.0 counts only the
    # strongest of a dependent set (Invariant 6). The trace says so directly:
    # under 0.1.0 both CONTRADICT links weigh 1.800000; under 0.2.0 the second
    # weighs 0.000000 with reason "dependent_strongest_only". The dropped one is
    # the only short contradiction, so that branch yields nothing and the
    # qualifier branch answers. Correct under both models, for different reasons.
    expect(plain_for(claim)[:say_instead]).to eq("The council banned bicycles on Market Street on Saturdays.")
  end

  it "prefers the strongest counted contradiction when the readings are independent" do
    claim = create_claim(curator, "The council banned bicycles.")
    link_evidence(curator, evidence(long, origin: "Minutes of the first meeting."), claim, direction: "CONTRADICT")
    link_evidence(curator, evidence("The ban covers Market Street on Saturdays only.", origin: "Minutes of the second meeting."), claim, direction: "CONTRADICT")

    # Separate passages, so nothing is collapsed and the contradiction branch has
    # a short candidate to offer. This is the same precedence as the case above,
    # reaching a different branch because the evidence differs — which is the
    # whole point of pinning both.
    expect(plain_for(claim)[:say_instead]).to eq("The ban covers Market Street on Saturdays only.")
  end
end
