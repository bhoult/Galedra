require "rails_helper"

RSpec.describe RecomputeAffectedScoresJob do
  include LedgerHelpers
  include GraphHelpers
  before { release_models }

  it "skips a claim that did not exist at the seq, instead of failing the whole job" do
    pair, = register_key
    source = create_source(pair)
    location = create_location(pair, source)
    early = Contribution.maximum(:seq)

    # The claim and its evidence come after the source, as they do in one
    # recorded investigation, so the source's seq reaches a claim not yet born.
    claim = create_claim(pair, "A claim recorded after its source.")
    link_evidence(pair, create_evidence(pair, location), claim)
    expect(claim.created_seq).to be > early

    expect { described_class.new.perform(early) }.not_to raise_error
    expect(ClaimScore.where(claim_id: claim.id, snapshot_seq: early)).to be_empty

    head = Contribution.maximum(:seq)
    expect { described_class.new.perform(head) }.not_to raise_error
    expect(Scoring::Score.call(claim, head, Scoring::Registry.default_model).assessment_state).to be_present
  end
end
