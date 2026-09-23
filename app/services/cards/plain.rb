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

    # Stage 35. A claim whose only evidence comes from the source it was taken
    # out of is not unevidenced in the ordinary way: what is there is provenance
    # rather than corroboration. Saying only "insufficient evidence" hides that,
    # and the obvious next step differs — this one wants an outside source, not
    # a first reading.
    #
    # Two sentences, because the original said "the quotation is faithful"
    # whenever every link was SELF, and inferred a check from where the evidence
    # came from. Extraction creates those links on its own: a claim with two
    # UNVERIFIED, never-audited links was telling readers its quotation had been
    # confirmed (reported in 01a0c0d5). Faithfulness is claimed only when an
    # audit actually confirmed it. The second sentence says "counted" rather
    # than "checked" because a documented null search is a check that counts
    # nothing, and the first version called that "nothing checked" to the
    # assistant that had just performed it.
    PROVENANCE_CONFIRMED = "The quotation is faithful to the source. No outside evidence has been counted."
    PROVENANCE_UNCHECKED = "The only evidence is the source the claim was taken from, which is where it came from rather than a check of it. " \
                           "No outside evidence has been counted."

    def call(claim, seq, model, result)
      headline = if result.assessment_state == "NOT_APPLICABLE"
        REASONS.fetch(result.not_applicable_reason, HEADLINES["NOT_APPLICABLE"])
      elsif provenance_only?(result)
        quotation_confirmed?(result) ? PROVENANCE_CONFIRMED : PROVENANCE_UNCHECKED
      else
        HEADLINES.fetch(result.assessment_state, Headline.for(result.assessment_state))
      end
      { headline: headline, say_instead: say_instead(claim, seq, model, result) }
    end

    # Every counted link drawn from an origin the claim came out of. Read from
    # the trace, which a model that weighs provenance marks per link, so this is
    # derived from the score rather than recomputed beside it and cannot drift
    # from what the number actually did.
    def provenance_only?(result)
      return false unless result.assessment_state == "INSUFFICIENT_EVIDENCE"

      links = result.trace.is_a?(Hash) ? result.trace["links"] : nil
      links.is_a?(Array) && links.any? && links.all? { |entry| entry["provenance"] == "SELF" }
    end

    # Someone audited the passage and it held. Never inferred from provenance:
    # SELF says where the evidence came from, not that anybody read it.
    def quotation_confirmed?(result)
      links = result.trace.is_a?(Hash) ? result.trace["links"] : nil
      links.is_a?(Array) && links.any? { |entry| entry["audit_confirmed"] == true }
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
      items = EvidenceItem.where(id: links.map { |l| l["evidence"] }).index_by(&:id)
      if %w[CONTRADICTED LEANS_CONTRADICTED].include?(result.assessment_state)
        text = links.select { |l| l["direction"] == "CONTRADICT" }.sort_by { |l| -BigDecimal(l["effective_weight"]) }
                    .map { |l| items[l["evidence"]] }.compact
                    .find { |e| short?(e.statement) && figures_backed?(e) }&.statement
        return text if text
      end
      claim.evidence_claim_links.effective_at(seq).where(direction: "QUALIFY").order(:created_seq).includes(:evidence_item).each do |qualifier|
        supported = qualified_version(claim, qualifier.evidence_item, seq, model)
        return supported.canonical_text if supported

        statement = qualifier.evidence_item.statement
        return statement if short?(statement) && figures_backed?(qualifier.evidence_item)
      end
      nil
    end

    def short?(text) = text.present? && text.split.size <= MAX_WORDS

    # A figure in the sentence has to be in the passage it rests on.
    #
    # say_instead is drafted to be repeated by someone who will not open the
    # card, so it is the one sentence here where taking the recorder's word is
    # most costly. A statement is the recorder's prose; only the excerpt is
    # quoted. On claim 16fb6733 the offered sentence read "Ipsos found 85% in
    # China and 37% in the US agree..." while its excerpt was the survey's
    # question stem and nothing else — the figures were right, and a reader
    # following them to the source found no way to check that (01a0c0ec).
    #
    # Digits only, and both sides normalised the way the quote verifier
    # normalises, so this cannot turn on typography. It filters what may be
    # offered for repetition; it does not touch scoring, and evidence with
    # figures elsewhere in its source stays counted exactly as before.
    # Takes the evidence rather than the excerpt so the passage is fetched only
    # when the sentence has a figure to check, which most do not: a card that
    # offers ordinary prose costs no extra query.
    def figures_backed?(evidence)
      numbers = evidence.statement.to_s.scan(/\d[\d,.]*/).map { |n| n.delete(",").sub(/\.0+\z/, "") }
      return true if numbers.empty?

      text = evidence.source_location&.excerpt.to_s.delete(",")
      numbers.all? { |n| text.include?(n) }
    end

    # The claim, other than this one, that the qualifying evidence supports
    # directly and that holds up: the version the qualifier points to.
    def qualified_version(claim, evidence, seq, model)
      candidates = evidence.evidence_claim_links.effective_at(seq).where(direction: "SUPPORT").where.not(claim_id: claim.id).order(:created_seq).includes(:claim)
                           .map(&:claim)
      first_holding(candidates.select { |other| short?(other.canonical_text) }, seq, model)
    end

    def narrower_supported(claim, seq, model)
      # Filtered from the memoised counted edges rather than by two more queries:
      # the result is sorted by created_seq just below, so the order these arrive
      # in does not decide anything (docs/profiler/2026-09-19-weaknesses-at-3000-claims.md).
      candidates = claim.counted_incoming_edges(seq).select { |e| e.relationship_type == "NARROWS" }.map(&:from_claim) +
                   claim.counted_outgoing_edges(seq).select { |e| e.relationship_type == "BROADENS" }.map(&:to_claim)
      first_holding(candidates.uniq.sort_by(&:created_seq), seq, model)
    end

    # The first of these, in the order given, that is not quarantined and holds
    # up. Asked for the set — one quarantine query, one scoring pass — where it
    # was a lookup and a score per candidate until one matched (Stage 26).
    def first_holding(candidates, seq, model)
      return nil if candidates.empty?

      withheld = Quarantine.live.where(target_type: "CLAIM", target_id: candidates.map(&:id)).pluck(:target_id).to_set
      open = candidates.reject { |other| withheld.include?(other.id) }
      scored = Scoring::Score.call_many(open, seq, model)
      open.find { |other| %w[SUPPORTED LEANS_SUPPORTED].include?((scored[other.id] || Scoring::Score.call(other, seq, model)).assessment_state) }
    end
  end
end
