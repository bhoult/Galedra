# Clears the score cache and recomputes every claim at the head under every
# released model. Admin-triggered (spec 06 §2 POST /admin/recompute).
class RecomputeAllScoresJob < ApplicationJob
  queue_as :default

  def perform(seq = Contribution.maximum(:seq))
    ClaimScore.delete_all
    models = Scoring::Registry.released.to_a
    Claim.where(Claim.arel_table[:created_seq].lteq(seq)).find_each do |claim|
      models.each { |model| Scoring::Score.call(claim, seq, model) }
    end
  end
end
