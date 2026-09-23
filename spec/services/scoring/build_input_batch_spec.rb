require "rails_helper"

# Stage 26. BuildInput.call_many must return, for every (claim, seq) pair, the
# bytes BuildInput.call returns for it: the input is what the scorer hashes, so
# a difference here is a different trace (Invariant 4).
RSpec.describe Scoring::BuildInputBatch do
  include GraphHelpers
  before { release_models }

  it "builds the same input as one claim at a time, for every claim at every checkpoint of the demo" do
    graph = build_public_demo
    seqs = graph.checkpoints.values.uniq.sort + [ Contribution.maximum(:seq) ]
    claims = Claim.all.to_a
    compared = 0
    seqs.each do |seq|
      pairs = claims.select { |c| c.created_seq <= seq }.map { |c| [ c, seq ] }
      batch = Scoring::BuildInput.call_many(pairs)
      pairs.each do |claim, s|
        expect(batch[claim.id].to_json).to eq(Scoring::BuildInput.call(claim, s).to_json), "#{graph.claims.key(claim) || claim.id} at seq #{s}"
        compared += 1
      end
    end
    # Pairs at different seqs in one batch, as Stage 38's watermarks make them.
    mixed = claims.each_with_index.map { |c, i| [ c, [ c.created_seq, seqs[i % seqs.size] ].max ] }
    batch = Scoring::BuildInput.call_many(mixed)
    mixed.each { |claim, s| expect(batch[claim.id].to_json).to eq(Scoring::BuildInput.call(claim, s).to_json) }
    expect(compared).to be > 20
  end
end
