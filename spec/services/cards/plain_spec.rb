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

  # say_instead is drafted to be repeated by someone who will not open the card,
  # so it is the one sentence where taking the recorder's word costs most. The
  # statement is the recorder's prose; only the excerpt is quoted. A card offered
  # "Ipsos found 85% in China and 37% in the US agree..." whose excerpt was the
  # survey's question stem and no figures at all (01a0c0ec). The numbers were
  # right; a reader following them to the source had no way to see that.
  it "does not offer a sentence whose figures are absent from the passage it rests on" do
    claim = create_claim(curator, "Most people everywhere distrust AI.")
    source = create_source(curator, content: "Products and services using artificial intelligence have more benefits than drawbacks. #{long}")
    unbacked = create_evidence(curator, create_location(curator, source, start: 0, finish: 85),
                               statement: "Ipsos found 85% in China and 37% in the US agree AI has more benefits.")
    link_evidence(curator, unbacked, claim, direction: "CONTRADICT")
    expect(plain_for(claim)).to eq(headline: "The evidence goes against this.", say_instead: nil)

    # The same sentence is offered once the passage carries the figures.
    backed_source = create_source(curator, content: "only 38% of respondents in the U.S. said yes, in comparison to 84% elsewhere. #{long}")
    backed = create_evidence(curator, create_location(curator, backed_source, start: 0, finish: 76),
                             statement: "Only 38% in the US said yes, against 84% elsewhere.")
    link_evidence(curator, backed, claim, direction: "CONTRADICT")
    expect(plain_for(claim)[:say_instead]).to eq("Only 38% in the US said yes, against 84% elsewhere.")
  end

  it "leaves a sentence with no figures in it alone" do
    claim = create_claim(curator, "The council banned bicycles.")
    link_evidence(curator, evidence("The minutes record no such ban."), claim, direction: "CONTRADICT")
    expect(plain_for(claim)[:say_instead]).to eq("The minutes record no such ban.")
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
