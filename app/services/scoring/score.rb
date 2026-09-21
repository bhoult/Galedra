# frozen_string_literal: true

module Scoring
  # Scores a claim as of a seq under a released model, through the cache.
  # The cached trace is the whole result, so a cache hit reproduces the same
  # bytes as a recomputation.
  module Score
    module_function

    # Stage 38: the cache is keyed on the claim's watermark — the last seq at
    # which anything bearing on its score moved — not on the seq asked for. The
    # score is computed at the watermark and the trace says so; a read at a
    # later seq gets that trace with `unchanged_since` beside it, which is a
    # truer answer than a recomputation at a seq where nothing had changed.
    def call(claim, seq, model)
      model = Registry.find(model) unless model.is_a?(ScoringModel)
      raise ActiveRecord::RecordNotFound, "claim did not exist at seq #{seq}" if claim.created_seq > seq

      cached = Watermark.hits([ claim.id ], seq, model.id).first
      return still_current(from_cache(cached), cached.snapshot_seq, seq) if cached

      at = Watermark.at(claim, seq)
      result = Registry.score(BuildInput.call(claim, at), model)
      store(claim, at, model, result)
      still_current(result, at, seq)
    end

    # Reported, never restamped. Saying the trace was computed at the seq that
    # was asked for would assert a computation that never happened.
    def still_current(result, at, seq)
      result.unchanged_since = at if at < seq
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

      # Each claim is keyed on its own watermark, so the cache is asked for a
      # set of (claim, seq) pairs — still one query.
      hits = lookup(claims, seq, model)
      misses = claims.reject { |c| hits.key?(c.id) }
      marks = marks_for(misses)
      at = misses.to_h { |c| [ c.id, Watermark.bound(marks[c.id], seq) ] }
      # Audit state is a function of the log up to this seq, and the log does
      # not move while the set is being scored; the same contributions recur
      # across links and across models, so ask once. The pass is built at the
      # seq asked for and used down to the oldest watermark in the set, which is
      # sound for the same reason the watermark itself is: every quarantine,
      # audit and revocation it holds would have moved the mark of any claim it
      # bears on (Scoring::Watermark).
      computed = Audits::Status.memoized { compute_misses(misses, at, seq, model) }

      claims.to_h do |c|
        row = hits[c.id]
        [ c.id, still_current(row ? from_cache(row) : computed[c.id], row ? row.snapshot_seq : at[c.id], seq) ]
      end
    end

    # In slices, because `Scoring::Pass` loads every counted link of the set it
    # is given, with its contribution — and a whole-graph pass hands it the
    # node. On the bench corpus at 100,024 claims that is one object graph of
    # hundreds of thousands of rows off the widest table in the schema, held
    # until the pass ends, and nothing reaches `claim_scores` until all of it is
    # scored. A slice at a time bounds the memory and lands the rows as it goes,
    # so a pass that is interrupted keeps what it computed. The answers are
    # identical: a pass is a memo of questions whose answers cannot change while
    # the log stands still (Invariant 4).
    SCORE_BATCH = 500

    def compute_misses(misses, at, seq, model)
      misses.each_slice(SCORE_BATCH).reduce({}) do |all, slice|
        computed = Pass.over(slice, seq, down_to: slice.map { |c| at[c.id] }.min || seq) do
          slice.to_h { |c| [ c.id, Registry.score(BuildInput.call(c, at[c.id]), model) ] }
        end
        store_all(computed, at, model)
        all.merge(computed)
      end
    end

    def recompute(claim, seq, model)
      ClaimScore.where(claim_id: claim.id, snapshot_seq: [ seq, Watermark.at(claim, seq) ].uniq, scoring_model_id: model.id).delete_all
      call(claim, seq, model)
    end

    def store(claim, seq, model, result)
      ClaimScore.upsert(row_for(claim.id, seq, model, result), unique_by: [ :claim_id, :snapshot_seq, :scoring_model_id ])
    end

    # Chunked: a trace is a whole JSON document, so a few hundred rows at a time
    # keeps one statement from carrying megabytes.
    STORE_BATCH = 250

    # And the same on the way in. A whole-graph pass hands `call_many` every
    # claim on the node — 100,024 of them on the bench corpus — and an IN list
    # that long is a statement of several megabytes before any row comes back.
    # A page of claims is well under one slice, so the ordinary case is still
    # one statement.
    LOOKUP_BATCH = 1_000

    def lookup(claims, seq, model)
      claims.each_slice(LOOKUP_BATCH)
            .flat_map { |slice| Watermark.hits(slice.map(&:id), seq, model.id).to_a }
            .index_by(&:claim_id)
    end

    def marks_for(claims)
      return {} if claims.empty?

      claims.each_slice(LOOKUP_BATCH).reduce({}) { |all, slice| all.merge(Watermark.marks(slice.map(&:id))) }
    end

    def store_all(results_by_claim_id, seq_by_claim_id, model)
      return if results_by_claim_id.empty?

      results_by_claim_id.each_slice(STORE_BATCH) do |slice|
        rows = slice.map { |claim_id, result| row_for(claim_id, seq_by_claim_id[claim_id], model, result) }
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
