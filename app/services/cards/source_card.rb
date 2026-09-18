# frozen_string_literal: true

module Cards
  # Per-source answer card (spec 06 §5, 08 §9): one card per claim extracted
  # from the source by a CLAIM_EXTRACTION task, plus a one-sentence roll-up.
  module SourceCard
    module_function

    def call(source, seq, model)
      claims = extracted_claims(source, seq)
      cards = claims.map do |claim|
        next { claim_id: claim.id, text: nil, quarantined: true } if Governance::Quarantines.live_for("CLAIM", claim.id)

        result = Scoring::Score.call(claim, seq, model)
        { claim_id: claim.id, text: claim.canonical_text, type: claim.claim_type, assessment_state: result.assessment_state,
          card: ClaimCard.call(claim, seq, model, result) }
      end
      { source_id: source.id, snapshot_seq: seq, model: model.full_name, cards: cards, summary: roll_up(cards),
        state_counts: cards.filter_map { |c| c[:assessment_state] }.tally.sort.to_h }
    end

    def extracted_claims(source, seq)
      task_ids = Task.where(target_type: "SOURCE", target_id: source.id, task_type: "CLAIM_EXTRACTION").select(:id)
      contribution_ids = Contribution.where(action_type: "TASK_RESULT", task_id: task_ids).select(:id)
      Claim.where(contribution_id: contribution_ids).or(Claim.where(extracted_from_source_id: source.id)).counted_at(seq).order(:created_seq)
    end

    def roll_up(cards)
      states = cards.filter_map { |c| c[:assessment_state] }
      return "No claims have been extracted from this source yet." if states.empty?

      counts = states.tally
      parts = []
      parts << "#{counts['UNRESOLVED']} unresolved" if counts["UNRESOLVED"]
      parts << "#{counts['LEANS_CONTRADICTED'] + counts.fetch('CONTRADICTED', 0)} leans contradicted or contradicted" if counts["LEANS_CONTRADICTED"] || counts["CONTRADICTED"]
      parts << "#{counts['SUPPORTED'] + counts.fetch('LEANS_SUPPORTED', 0)} supported or leans supported" if counts["SUPPORTED"] || counts["LEANS_SUPPORTED"]
      parts << "#{counts['INSUFFICIENT_EVIDENCE']} with insufficient evidence" if counts["INSUFFICIENT_EVIDENCE"]
      model_dependent = cards.count { |c| c.dig(:card, :labels)&.any? { |l| l.include?("modeling choices") } }
      parts << "#{model_dependent} model-dependent" if model_dependent.positive?
      parts << "#{counts['NOT_APPLICABLE']} not scored (value judgment or non-empirical)" if counts["NOT_APPLICABLE"]
      "#{states.size} claim#{'s' if states.size != 1} checked: #{parts.join(', ')}."
    end
  end
end
