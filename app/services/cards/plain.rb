# frozen_string_literal: true

module Cards
  # Plain-language fields for people with thirty seconds (Stage 13): a
  # headline in everyday words and, when the graph supports one, a sentence
  # to say instead. Rule-based from the score result, like the stub summary;
  # neutral wording (06 §4 rule 12): never "true", "false", or "debunked".
  module Plain
    HEADLINES = {
      "SUPPORTED" => "Checks out so far.",
      "LEANS_SUPPORTED" => "Probably holds up, but it is not settled.",
      "UNRESOLVED" => "The evidence is mixed. Don't repeat this as settled.",
      "LEANS_CONTRADICTED" => "The evidence leans against this.",
      "CONTRADICTED" => "The evidence goes against this.",
      "INSUFFICIENT_EVIDENCE" => "Nobody has checked this yet.",
      "NOT_APPLICABLE" => "This is not a checkable fact.",
      "QUARANTINED" => "Withheld by moderation."
    }.freeze
    REASONS = {
      "NORMATIVE_OR_VALUE" => "This is an opinion about what should happen, not a fact to check.",
      "METAPHYSICAL" => "This is a belief, not something evidence can settle.",
      "RHETORICAL" => "This is a figure of speech, not a factual claim.",
      "UNRESOLVED_FORECAST" => "This is a prediction; nobody can check it yet.",
      "NO_LEGAL_MODEL" => "This is a legal question; Galedra does not score those yet."
    }.freeze

    module_function

    def call(claim, seq, model, result)
      headline = if result.assessment_state == "NOT_APPLICABLE"
        REASONS.fetch(result.not_applicable_reason, HEADLINES["NOT_APPLICABLE"])
      else
        HEADLINES.fetch(result.assessment_state, Headline.for(result.assessment_state))
      end
      { headline: headline, say_instead: say_instead(claim, seq, model, result) }
    end

    # In order: a narrower claim that holds up; the strongest counted
    # contradiction; a counted qualifier. Otherwise nothing: no sentence is
    # invented.
    def say_instead(claim, seq, model, result)
      narrower = narrower_supported(claim, seq, model)
      return narrower.canonical_text if narrower

      links = result.trace["links"].select { |l| l["effective_weight"] && BigDecimal(l["effective_weight"]).positive? }
      statements = EvidenceItem.where(id: links.map { |l| l["evidence"] }).pluck(:id, :statement).to_h
      if %w[CONTRADICTED LEANS_CONTRADICTED].include?(result.assessment_state)
        strongest = links.select { |l| l["direction"] == "CONTRADICT" }.max_by { |l| BigDecimal(l["effective_weight"]) }
        return statements[strongest["evidence"]] if strongest && statements[strongest["evidence"]]
      end
      qualifier = claim.evidence_claim_links.effective_at(seq).where(direction: "QUALIFY").order(:created_seq).first
      return qualifier.evidence_item.statement if qualifier&.evidence_item&.statement.present?

      nil
    end

    def narrower_supported(claim, seq, model)
      candidates = claim.incoming_edges.counted_at(seq).where(relationship_type: "NARROWS").includes(:from_claim).map(&:from_claim) +
                   claim.outgoing_edges.counted_at(seq).where(relationship_type: "BROADENS").includes(:to_claim).map(&:to_claim)
      candidates.uniq.sort_by(&:created_seq).find do |other|
        next false if Governance::Quarantines.live_for("CLAIM", other.id)

        %w[SUPPORTED LEANS_SUPPORTED].include?(Scoring::Score.call(other, seq, model).assessment_state)
      end
    end
  end
end
