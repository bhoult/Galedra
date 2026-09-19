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

    # Many claims at one seq under one model, with one query for the cache and
    # one insert for what it did not hold (Stage 26). The per-claim path asked
    # for each claim separately, which was 70% of the wall time of a
    # whole-graph report and nearly all of it misses: the cache is keyed on the
    # exact seq and the head seq moves with every append, so the report paid a
    # round trip to learn nothing and then computed anyway.
    #
    # Same inputs, same scorer, same trace: this changes when the database is
    # asked, never what is computed (Invariant 4).
    # Returns {claim_id => Calculate::Result}.
    def call_many(claims, seq, model)
      model = Registry.find(model) unless model.is_a?(ScoringModel)
      claims = claims.reject { |c| c.created_seq > seq }
      return {} if claims.empty?

      hits = ClaimScore.where(claim_id: claims.map(&:id), snapshot_seq: seq, scoring_model_id: model.id).index_by(&:claim_id)
      misses = claims.reject { |c| hits.key?(c.id) }
      # Audit state is a function of the log up to this seq, and the log does
      # not move while the set is being scored; the same contributions recur
      # across links and across models, so ask once.
      computed = Audits::Status.memoized do
        misses.to_h { |c| [ c.id, Registry.score(BuildInput.call(c, seq), model) ] }
      end
      store_all(computed, seq, model)

      claims.to_h { |c| [ c.id, hits[c.id] ? from_cache(hits[c.id]) : computed[c.id] ] }
    end

    def recompute(claim, seq, model)
      ClaimScore.where(claim_id: claim.id, snapshot_seq: seq, scoring_model_id: model.id).delete_all
      call(claim, seq, model)
    end

    def store(claim, seq, model, result)
      ClaimScore.upsert(row_for(claim.id, seq, model, result), unique_by: [ :claim_id, :snapshot_seq, :scoring_model_id ])
    end

    # Chunked: a trace is a whole JSON document, so a few hundred rows at a time
    # keeps one statement from carrying megabytes.
    STORE_BATCH = 250

    def store_all(results_by_claim_id, seq, model)
      return if results_by_claim_id.empty?

      results_by_claim_id.each_slice(STORE_BATCH) do |slice|
        rows = slice.map { |claim_id, result| row_for(claim_id, seq, model, result) }
        ClaimScore.upsert_all(rows, unique_by: [ :claim_id, :snapshot_seq, :scoring_model_id ])
      end
    end

    def row_for(claim_id, seq, model, result)
      {
        id: SecureRandom.uuid_v7, claim_id: claim_id, snapshot_seq: seq, scoring_model_id: model.id,
        assessment_state: result.assessment_state, probability: result.probability, review_coverage: result.review_coverage,
        stability: result.stability, support_groups: result.support_groups, contradict_groups: result.contradict_groups,
        contested: result.contested, provisional: result.provisional, trace: result.trace, trace_hash: result.trace_hash,
        computed_at: Time.current
      }
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
