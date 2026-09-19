# frozen_string_literal: true

module Weaknesses
  # The Weaknesses page (spec 06 §5, constitution Art. XXII): seven deterministic
  # lists over accepted, live, unquarantined claims at a seq, each entry carrying
  # the "what would most change this" item from Cards::Why.
  module Report
    KINDS = %w[low_coverage_scored provisional independence_unreviewed contested models_disagree high_impact_insufficient disputed_audits].freeze
    HIGH_DOWNSTREAM = 3

    module_function

    def call(seq, kind: nil, limit: 50)
      model = Scoring::Registry.default_model
      models = Scoring::Registry.released.to_a
      kinds = kind ? [ kind ] : KINDS
      raise Ledger::Rejected.new([ { code: "SCHEMA_INVALID", path: "$.kind", detail: "expected one of #{KINDS.join(', ')}" } ]) unless (kinds - KINDS).empty?

      claims = Claim.counted_at(seq).where.not(id: Governance::Quarantines.quarantined_claim_ids).order(:created_seq).to_a
      scored = claims.to_h { |c| [ c.id, Scoring::Score.call(c, seq, model) ] }
      lists = kinds.to_h do |k|
        entries = send(k, claims, scored, seq, model, models).first(limit)
        [ k, entries.map { |claim, detail| entry(claim, scored[claim.id], detail, seq, model) } ]
      end
      { snapshot_seq: seq, model: model.full_name, kinds: KINDS, lists: lists }
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

    def models_disagree(claims, scored, seq, _model, models)
      claims.filter_map do |c|
        states = models.to_h { |m| [ m.full_name, Scoring::Score.call(c, seq, m).assessment_state ] }
        [ c, { states: states } ] if states.values.uniq.size > 1
      end
    end

    def high_impact_insufficient(claims, scored, seq, *)
      claims.filter_map do |c|
        downstream = ClaimEdge.counted_at(seq).where(from_claim_id: c.id).count
        [ c, { downstream_count: downstream } ] if scored[c.id].assessment_state == "INSUFFICIENT_EVIDENCE" && downstream >= HIGH_DOWNSTREAM
      end
    end

    def disputed_audits(claims, _scored, seq, *)
      claims.filter_map do |c|
        links = c.evidence_claim_links.effective_at(seq)
        audits = Audit.disputed_for(links.map(&:contribution_id), seq).to_a
        # Overturned as of this seq, not merely overturned at some later one.
        [ c, { audits: audits.map { |a| { audit_id: a.id, result: a.result, overturned: !a.active_at?(seq) } } } ] if audits.any?
      end
    end
  end
end
