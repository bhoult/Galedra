# frozen_string_literal: true

module Scoring
  # Scores a claim as of a seq under a released model, through the cache.
  # The cached trace is the whole result, so a cache hit reproduces the same
  # bytes as a recomputation.
  module Score
    module_function

    def call(claim, seq, model)
      model = Registry.find(model) unless model.is_a?(ScoringModel)
      raise ActiveRecord::RecordNotFound, "claim did not exist at seq #{seq}" if claim.created_seq > seq

      cached = ClaimScore.find_by(claim_id: claim.id, snapshot_seq: seq, scoring_model_id: model.id)
      return from_cache(cached) if cached

      result = Registry.score(BuildInput.call(claim, seq), model)
      store(claim, seq, model, result)
      result
    end

    def recompute(claim, seq, model)
      ClaimScore.where(claim_id: claim.id, snapshot_seq: seq, scoring_model_id: model.id).delete_all
      call(claim, seq, model)
    end

    def store(claim, seq, model, result)
      ClaimScore.upsert(
        {
          id: SecureRandom.uuid_v7, claim_id: claim.id, snapshot_seq: seq, scoring_model_id: model.id,
          assessment_state: result.assessment_state, probability: result.probability, review_coverage: result.review_coverage,
          stability: result.stability, support_groups: result.support_groups, contradict_groups: result.contradict_groups,
          contested: result.contested, provisional: result.provisional, trace: result.trace, trace_hash: result.trace_hash,
          computed_at: Time.current
        },
        unique_by: [ :claim_id, :snapshot_seq, :scoring_model_id ]
      )
    end

    def from_cache(row)
      t = row.trace
      Calculate::Result.new(
        assessment_state: t["assessment_state"], probability: t["probability"], review_coverage: t["review_coverage"],
        review_checklist: t["review_checklist"], stability: t["stability"], support_groups: t["support_groups"],
        contradict_groups: t["contradict_groups"], independence_unreviewed: t["independence_unreviewed"],
        contested: t["contested"], provisional: t["provisional"], not_applicable_reason: t["not_applicable_reason"],
        model_dependent: t["model_dependent"], trace: t, trace_hash: row.trace_hash
      )
    end
  end
end
