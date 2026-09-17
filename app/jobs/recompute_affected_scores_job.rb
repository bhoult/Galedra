# Recomputes cached scores for the claims a contribution affected, at that
# seq, under every released model (spec 11 §7). Idempotent: the cache is
# keyed by (claim, seq, model) and upserted.
class RecomputeAffectedScoresJob < ApplicationJob
  queue_as :default

  def perform(seq)
    contribution = Contribution.find_by(seq: seq)
    return if contribution.nil?

    models = Scoring::Registry.released.to_a
    Claim.where(id: Scoring::Affected.claim_ids(contribution)).find_each do |claim|
      models.each { |model| Scoring::Score.recompute(claim, seq, model) }
    end
  end
end
