# frozen_string_literal: true

module Investigations
  # The statement as a whole (owner request, after Stage 19): a rule-based
  # reading of the claims' states, in the plain-headline vocabulary, with the
  # counts that justify it. The number is the product of the checkable claims'
  # probabilities, i.e. the model's figure for every checkable claim holding at
  # once, treating them as independent, stated with model and snapshot and
  # labelled as such. Claim scores are unchanged; this is display composition.
  module Verdict
    AGAINST = %w[CONTRADICTED LEANS_CONTRADICTED].freeze
    FOR = %w[SUPPORTED LEANS_SUPPORTED].freeze
    OPEN = %w[UNRESOLVED INSUFFICIENT_EVIDENCE].freeze

    module_function

    # The badge for the statement as a whole, on the same ten-level scale as a claim.
    def badge_for(states, results, checkable:, against:, holds:, open:)
      return :not_checkable if checkable.zero?
      if against == checkable
        return states.all? { |s| s == "CONTRADICTED" } ? :strongly_against : :mostly_against
      end
      return against * 2 >= checkable ? :mostly_against : :leans_against if against.positive?
      return holds.positive? ? :mixed : :not_checked if open.positive?

      strong = results.all? { |r| r.assessment_state == "SUPPORTED" && r.probability && BigDecimal(r.probability) >= BigDecimal("0.9") }
      return :strongly_supported if strong

      states.all?("SUPPORTED") ? :mostly_supported : :leans_supported
    end

    def call(claims, seq, model)
      results = claims.map { |c| Scoring::Score.call(c, seq, model) }
      states = results.map(&:assessment_state)
      not_checkable = states.count("NOT_APPLICABLE")
      checkable = states.size - not_checkable
      against = states.count { |s| AGAINST.include?(s) }
      holds = states.count { |s| FOR.include?(s) }
      open = states.count { |s| OPEN.include?(s) }
      headline = if checkable.zero? then "Nothing here is a checkable fact."
      elsif against == checkable then "The evidence goes against this."
      elsif against.positive? then "Parts of this go against the evidence."
      elsif open.positive? then holds.positive? ? "Parts of this hold up; the rest is not settled." : "Not settled yet."
      else "Checks out so far."
      end
      parts = []
      parts << "#{against} of #{checkable} checkable #{'claim'.pluralize(checkable)} #{against == 1 ? 'goes' : 'go'} against the evidence" if against.positive?
      parts << "#{holds} #{holds == 1 ? 'holds' : 'hold'} up so far" if holds.positive?
      parts << "#{open} not yet settled" if open.positive?
      parts << "#{not_checkable} not a checkable fact" if not_checkable.positive?
      probabilities = results.filter_map { |r| r.probability && BigDecimal(r.probability) }
      stated = if checkable.positive? && probabilities.size == checkable
        product = probabilities.reduce(BigDecimal("1")) { |a, b| a * b }
        "#{Scoring::Decimal.fixed(product, 4)} under #{model.full_name} at snapshot #{seq} for all claims together"
      end
      badge = badge_for(states, results, checkable: checkable, against: against, holds: holds, open: open)
      { headline: headline, sentence: parts.join("; "), stated: stated, badge: badge,
        counts: { claims: states.size, checkable: checkable, against: against, holds: holds, open: open, not_checkable: not_checkable },
        note: "The number is the model's figure for every checkable claim holding at once, treating them as independent." }
    end
  end
end
