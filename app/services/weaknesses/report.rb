# frozen_string_literal: true

module Weaknesses
  # The Weaknesses page (spec 06 §5, constitution Art. XXII): seven deterministic
  # lists over accepted, live, unquarantined claims at a seq, each entry carrying
  # the "what would most change this" item from Cards::Why.
  module Report
    KINDS = %w[low_coverage_scored provisional independence_unreviewed contested models_disagree high_impact_insufficient disputed_audits].freeze
    HIGH_DOWNSTREAM = 3
    CACHE_FOR = 1.hour

    module_function

    # The report reads the whole graph, so it is computed once per snapshot and
    # model rather than once per view (Stage 26). A snapshot's answer never
    # changes, so the cache is keyed by seq and needs no invalidation; the TTL
    # only bounds how long a superseded snapshot's answer occupies the store.
    def call(seq, kind: nil, limit: 50)
      model = Scoring::Registry.default_model
      kinds = kind ? [ kind ] : KINDS
      raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$.kind", detail: "expected one of #{KINDS.join(', ')}" } ]) unless (kinds - KINDS).empty?

      Rails.cache.fetch([ "weaknesses", seq, model&.full_name, kinds.join(","), limit ], expires_in: CACHE_FOR) do
        compute(seq, kinds, limit, model)
      end
    end

    def compute(seq, kinds, limit, model)
      models = Scoring::Registry.released.to_a
      claims = Claim.counted_at(seq).where.not(id: Governance::Quarantines.quarantined_claim_ids).order(:created_seq).to_a
      scored = claims.to_h { |c| [ c.id, Scoring::Score.call(c, seq, model) ] }
      facts = Facts.new(claims, seq)
      lists = kinds.to_h do |k|
        entries = send(k, claims, scored, seq, model, models, facts).first(limit)
        [ k, entries.map { |claim, detail| entry(claim, scored[claim.id], detail, seq, model) } ]
      end
      { snapshot_seq: seq, model: model&.full_name, kinds: KINDS, lists: lists }
    end

    # The set queries the per-claim lists used to issue one at a time.
    class Facts
      def initialize(claims, seq)
        ids = claims.map(&:id)
        @downstream = ClaimEdge.counted_at(seq).where(from_claim_id: ids).group(:from_claim_id).count
        links = EvidenceClaimLink.effective_at(seq).where(claim_id: ids).pluck(:claim_id, :contribution_id)
        @evidenced = links.map(&:first).uniq.to_set
        by_contribution = links.group_by(&:last)
        @audits = Hash.new { |h, k| h[k] = [] }
        Audit.disputed_for(by_contribution.keys, seq).each do |audit|
          by_contribution.fetch(audit.target_contribution_id, []).each { |claim_id, _| @audits[claim_id] << audit }
        end
      end

      def downstream(claim_id) = @downstream.fetch(claim_id, 0)
      def audits(claim_id) = @audits[claim_id]
      # A claim with no counted evidence reads INSUFFICIENT_EVIDENCE under every
      # model (Invariant 5), so no two models can disagree about it.
      def evidenced?(claim_id) = @evidenced.include?(claim_id)
    end

    def entry(claim, result, detail, seq, model)
      { claim_id: claim.id, text: claim.canonical_text, assessment_state: result.assessment_state, detail: detail,
        what_would_most_change_this: Cards::Why.most_moving_addition(claim, seq, model, result)&.slice(:direction, :observation, :state_from, :state_to, :text) }
    end

    def low_coverage_scored(claims, scored, *)
      claims.filter_map do |c|
        r = scored[c.id]
        done = Cards::DisplayRules.checks_done(r.review_checklist)
        [ c, { review_checks_done: done } ] if r.probability && done <= 1
      end
    end

    def provisional(claims, scored, *)
      claims.filter_map { |c| [ c, { provisional: true } ] if scored[c.id].provisional }
    end

    def independence_unreviewed(claims, scored, *)
      claims.filter_map { |c| [ c, { independence_unreviewed: scored[c.id].independence_unreviewed } ] if scored[c.id].independence_unreviewed.positive? }
    end

    def contested(claims, scored, *)
      claims.filter_map { |c| [ c, { support_groups: scored[c.id].support_groups, contradict_groups: scored[c.id].contradict_groups } ] if scored[c.id].contested }
    end

    def models_disagree(claims, scored, seq, _model, models, facts)
      claims.filter_map do |c|
        next unless facts.evidenced?(c.id)

        states = models.to_h { |m| [ m.full_name, Scoring::Score.call(c, seq, m).assessment_state ] }
        [ c, { states: states } ] if states.values.uniq.size > 1
      end
    end

    def high_impact_insufficient(claims, scored, seq, _model, _models, facts)
      claims.filter_map do |c|
        next unless scored[c.id].assessment_state == "INSUFFICIENT_EVIDENCE"

        downstream = facts.downstream(c.id)
        [ c, { downstream_count: downstream } ] if downstream >= HIGH_DOWNSTREAM
      end
    end

    def disputed_audits(claims, _scored, seq, _model, _models, facts)
      claims.filter_map do |c|
        audits = facts.audits(c.id)
        # Overturned as of this seq, not merely overturned at some later one.
        [ c, { audits: audits.map { |a| { audit_id: a.id, result: a.result, overturned: !a.active_at?(seq) } } } ] if audits.any?
      end
    end
  end
end
