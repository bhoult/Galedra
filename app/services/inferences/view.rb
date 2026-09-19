# frozen_string_literal: true

module Inferences
  # Inferences around a claim at a seq (Stage 25): those concluding it and
  # those using it as a premise, each premise with its current state and the
  # weakest premise marked (the one furthest from what its polarity needs; a
  # FAILS premise that reads supported is the weakest of all). Display only.
  module View
    RANK = { "SUPPORTED" => 0, "LEANS_SUPPORTED" => 1, "UNRESOLVED" => 2, "INSUFFICIENT_EVIDENCE" => 2, "NOT_APPLICABLE" => 2, "LEANS_CONTRADICTED" => 3, "CONTRADICTED" => 4 }.freeze

    module_function

    def for_claim(claim, seq, model = Scoring::Registry.default_model)
      concluded = Inference.counted_at(seq).where(conclusion_claim_id: claim.id).order(:created_seq).map { |i| present(i, seq, model) }
      premise_in = Inference.counted_at(seq).where(id: InferencePremise.counted_at(seq).where(claim_id: claim.id).select(:inference_id)).order(:created_seq).map { |i| present(i, seq, model) }
      { concluded_from: concluded, premise_in: premise_in, note: Inference::NOTE }
    end

    def present(inference, seq, model)
      premises = inference.premises.counted_at(seq).order(:position).includes(:claim).map do |pr|
        state = model && !Governance::Quarantines.live_for("CLAIM", pr.claim_id) ? Scoring::Score.call(pr.claim, seq, model).assessment_state : nil
        { id: pr.id, claim_id: pr.claim_id, text: pr.claim.canonical_text, polarity: pr.polarity, state: state, distance: distance(pr.polarity, state) }
      end
      weakest = premises.max_by { |p| p[:distance] }
      premises.each { |p| p[:weakest] = weakest && p[:id] == weakest[:id] && weakest[:distance].positive? }
      conclusion = inference.conclusion
      { id: inference.id, conclusion: { claim_id: conclusion.id, text: conclusion.canonical_text }, inference_type: inference.inference_type, strength: inference.strength,
        rule: inference.rule, premises: premises, weakest_premise_id: (weakest[:id] if weakest && weakest[:distance].positive?), created_seq: inference.created_seq, contribution_id: inference.contribution_id }
    end

    # 0 when the premise reads exactly what its polarity needs; 4 when it reads the opposite.
    def distance(polarity, state)
      rank = RANK.fetch(state, 2)
      polarity == "HOLDS" ? rank : 4 - rank
    end

    # Inferences whose conclusion reads supported while a premise reads the opposite of its polarity (Article XXII).
    def strained(seq, model = Scoring::Registry.default_model)
      Inference.counted_at(seq).order(:created_seq).filter_map do |inference|
        next if Governance::Quarantines.live_for("CLAIM", inference.conclusion_claim_id)

        conclusion_state = Scoring::Score.call(inference.conclusion, seq, model).assessment_state
        next unless %w[SUPPORTED LEANS_SUPPORTED].include?(conclusion_state)

        presented = present(inference, seq, model)
        bad = presented[:premises].select { |p| p[:distance] >= 3 }
        [ presented, conclusion_state, bad ] if bad.any?
      end
    end
  end
end
