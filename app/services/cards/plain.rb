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

    # A sentence to say instead is offered only when the claim as stated does
    # not hold up: a supported claim is itself what to say. Candidates, in
    # order: a narrower claim that holds up; the strongest counted
    # contradiction; for a counted qualifier, a claim that the same evidence
    # supports and that holds up, else its statement. Anything longer than
    # MAX_WORDS is skipped: the sentence is for a post, not a paper. Otherwise
    # nothing: no sentence is invented and none is cut short.
    MAX_WORDS = 25

    def say_instead(claim, seq, model, result)
      return nil if %w[SUPPORTED LEANS_SUPPORTED].include?(result.assessment_state)

      narrower = narrower_supported(claim, seq, model)
      return narrower.canonical_text if narrower && short?(narrower.canonical_text)

      links = result.trace["links"].select { |l| l["effective_weight"] && BigDecimal(l["effective_weight"]).positive? }
      statements = EvidenceItem.where(id: links.map { |l| l["evidence"] }).pluck(:id, :statement).to_h
      if %w[CONTRADICTED LEANS_CONTRADICTED].include?(result.assessment_state)
        text = links.select { |l| l["direction"] == "CONTRADICT" }.sort_by { |l| -BigDecimal(l["effective_weight"]) }
                    .map { |l| statements[l["evidence"]] }.find { |t| short?(t) }
        return text if text
      end
      claim.evidence_claim_links.effective_at(seq).where(direction: "QUALIFY").order(:created_seq).includes(:evidence_item).each do |qualifier|
        supported = qualified_version(claim, qualifier.evidence_item, seq, model)
        return supported.canonical_text if supported
        return qualifier.evidence_item.statement if short?(qualifier.evidence_item.statement)
      end
      nil
    end

    def short?(text) = text.present? && text.split.size <= MAX_WORDS

    # The claim, other than this one, that the qualifying evidence supports
    # directly and that holds up: the version the qualifier points to.
    def qualified_version(claim, evidence, seq, model)
      evidence.evidence_claim_links.effective_at(seq).where(direction: "SUPPORT").where.not(claim_id: claim.id).order(:created_seq).includes(:claim)
              .map(&:claim).find do |other|
        next false if Governance::Quarantines.live_for("CLAIM", other.id) || !short?(other.canonical_text)

        %w[SUPPORTED LEANS_SUPPORTED].include?(Scoring::Score.call(other, seq, model).assessment_state)
      end
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
