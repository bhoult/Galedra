# frozen_string_literal: true

module Investigations
  # Stage 45: what a check shows while its claims carry only an assistant's
  # first reading. Display composition beside the scores, never an input to
  # them: Verdict, the badge, the figure and Investigation.summary are computed
  # exactly as before, and this decides only what is said next to them.
  #
  # A check is *preliminary* while every checkable claim in it still sits at
  # INSUFFICIENT_EVIDENCE and at least one carries a first reading recorded with
  # this check. Once any claim has a state from evidence, the share line and the
  # top card are today's, built from scores alone, and each first reading moves
  # beneath its claim's own state — with the disagreement said aloud where the
  # two point opposite ways (Article XIX).
  module Preliminary
    LABEL = "Preliminary · an assistant's first reading, not yet checked against sources."
    LEADS_NOTE = "Links the assistant cited; Galedra has not read them."
    SHARE_PREFIX = "Preliminary (AI, not yet sourced)"

    module_function

    # This check's own first readings, by claim id. A claim reached through
    # attach_to can carry readings from several checks; the check page shows
    # only the ones recorded with it, and the claim page shows them all.
    def for_investigation(investigation, seq)
      ids = investigation.preliminary_contribution_ids
      return {} if ids.blank?

      PreliminaryResult.counted_at(seq).where(contribution_id: ids).order(:created_seq).index_by(&:claim_id)
    end

    # { preliminary:, phrase:, sentence: } for a set of claims and their scores.
    # A reading that was taken down keeps its stub beneath its claim, but its
    # expectation survives redaction, so it is left out here: otherwise the
    # share line, og tags and card would go on repeating what was removed.
    def reading(claims, results, by_claim)
      shown = by_claim.reject { |_, pre| pre.redacted_by_seq }
      checkable = claims.reject { |c| results[c.id]&.assessment_state == "NOT_APPLICABLE" }
      open = checkable.all? { |c| results[c.id]&.assessment_state == "INSUFFICIENT_EVIDENCE" }
      preliminary = checkable.any? && open && checkable.any? { |c| shown[c.id] }
      expectations = checkable.filter_map { |c| shown[c.id]&.expectation }
      { preliminary: preliminary, phrase: phrase(expectations), sentence: sentence(checkable, shown) }
    end

    # The whole statement in a few words, by the same counting rule Verdict
    # uses — one part expected against makes the whole "only in part" — and
    # never as a badge. No overall judgment is stored: the statement is not a
    # log object, and a count of the parts says what they add up to.
    def phrase(expectations)
      said = expectations - %w[NO_EXPECTATION]
      return PreliminaryResult::WORDS.fetch("NO_EXPECTATION") if said.empty?
      # One part that said something speaks for itself, whatever the parts
      # with no expectation beside it: "in part" stays "in part".
      return PreliminaryResult::WORDS.fetch(said.first) if said.size == 1
      return "expected not to hold up" if said.all?("EXPECTED_NOT_TO_HOLD")
      return "expected to hold up only in part" if said.include?("EXPECTED_NOT_TO_HOLD")
      return "expected to mostly hold up" if said.include?("EXPECTED_TO_HOLD_IN_PART")

      "expected to hold up"
    end

    def sentence(checkable, by_claim)
      return nil if checkable.empty?

      if checkable.size == 1
        pre = by_claim[checkable.first.id]
        return pre && "An assistant's first reading: #{pre.words}. It has not been checked against a source yet."
      end
      tally = checkable.map { |c| by_claim[c.id]&.expectation }.tally
      expects = [ [ "EXPECTED_TO_HOLD", "to hold up" ], [ "EXPECTED_TO_HOLD_IN_PART", "to hold up in part" ], [ "EXPECTED_NOT_TO_HOLD", "not to hold up" ] ]
                .filter_map { |key, words| "#{tally[key]} #{words}" if tally[key] }
      parts = []
      parts << "Of these #{checkable.size} parts, an assistant expects #{expects.to_sentence}." if expects.any?
      parts << "It has no expectation either way on #{tally['NO_EXPECTATION']}." if tally["NO_EXPECTATION"]
      parts << "#{tally[nil]} #{tally[nil] == 1 ? 'has' : 'have'} no first reading." if tally[nil]
      parts << "None has been checked against a source yet."
      parts.join(" ")
    end

    # Beneath a claim that has a state of its own. Where the reading and the
    # evidence point opposite ways the line says so, rather than quietly
    # replacing one with the other: a first reading the sources overturned is
    # information about how far a thirty-second check can be trusted.
    def beneath(pre, state)
      if pre.redacted_by_seq
        "A first reading of this claim was taken down."
      elsif pre.expectation == "EXPECTED_TO_HOLD" && Verdict::AGAINST.include?(state)
        "The first reading expected this to hold up; the sources so far lean against it."
      elsif pre.expectation == "EXPECTED_NOT_TO_HOLD" && Verdict::FOR.include?(state)
        "The first reading expected this not to hold up; the sources so far lean towards it."
      else
        "Preliminary: #{pre.words}."
      end
    end

    # What a model is shown as: as declared, never verified (Stage 27's rule).
    def declared(pre)
      return "taken down" if pre.redacted_by_seq

      pre.model.present? ? "#{pre.model}, as declared" : "model not declared"
    end
  end
end
