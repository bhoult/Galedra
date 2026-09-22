# Recomputes cached scores for the claims a contribution affected, at that
# seq, under every released model (spec 11 §7). Idempotent: the cache is
# keyed by (claim, seq, model) and upserted.
class RecomputeAffectedScoresJob < ApplicationJob
  queue_as :default

  def perform(seq)
    contribution = Contribution.find_by(seq: seq)
    return if contribution.nil?

    models = Scoring::Registry.released.to_a
    # Affected claims are found from the graph as it stands now, so a
    # contribution early in a recorded investigation reaches claims that were
    # written later in the same call. Those have no score at this seq, because
    # they did not exist at it, and asking for one raised RecordNotFound and
    # failed the job. Skipping them is the answer: there is nothing to
    # recompute, not an error.
    # The same map the watermark stamps with, or the two drift: a placement, a
    # check result or an edge moves the mark — invalidating the cache — while
    # this job warms a different set and the reader pays the cold score the
    # keying exists to avoid (code review, 2026-09-22).
    Claim.where(id: Scoring::Watermark.claim_ids(contribution)).where(created_seq: ..seq).find_each do |claim|
      models.each { |model| Scoring::Score.recompute(claim, seq, model) }
    end
  end
end
