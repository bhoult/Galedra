# Clears the score cache and recomputes every claim at the head under every
# released model. Admin-triggered (spec 06 §2 POST /admin/recompute).
#
# Stage 39, finding 5: this scored one claim at a time, once per model, so it
# inherited every per-row query in `Scoring::BuildInput` and then rebuilt the
# same input for each of the four released models — three-quarters of the
# assembly thrown away, and assembly is 96% of a cold score. `Scoring::Score.rescore`
# builds each claim's input once and scores it under every model, in slices.
#
# A rescore is what happens after a model release, so this is the path that
# decides whether releasing a model is an afternoon or a weekend.
class RecomputeAllScoresJob < ApplicationJob
  queue_as :default

  BATCH = 500

  def perform(seq = Contribution.maximum(:seq))
    ClaimScore.delete_all
    models = Scoring::Registry.released.to_a
    Claim.where(Claim.arel_table[:created_seq].lteq(seq)).find_in_batches(batch_size: BATCH) do |claims|
      Scoring::Score.rescore(claims, seq, models)
    end
  end
end
