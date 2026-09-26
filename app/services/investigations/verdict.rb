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
    #
    # An investigation is one statement, so one part against the evidence makes
    # the whole lean against it. An outline section is a collection of separate
    # statements, where that rule read 54 claims, 36 holding and 6 against, as
    # "Leans against"; a collection's badge comes from its figure instead
    # (collection_badge).
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

    # A collection's badge is read from its figure, through the model's own
    # state bands, so the badge and the number beside it can never disagree
    # (owner, 2026-09-23: "shouldn't the badges be based on the score?"). A
    # proportion rule came first and read differently from the average beside
    # it. With too little scored to have a figure, it is "not checked yet".
    def collection_badge(figure, checkable, model)
      return :not_checkable if checkable.zero?
      return :not_checked if figure.nil?

      Cards::Badge.level_for(band(BigDecimal(figure), model), figure)
    end

    # The state a single claim with this probability would sit in, by the
    # model's thresholds, ignoring the directional-evidence rule, which has no
    # meaning for an average.
    def band(value, model)
      t = model.config.fetch("state_thresholds")
      if value >= BigDecimal(t["SUPPORTED"]) then "SUPPORTED"
      elsif value >= BigDecimal(t["LEANS_SUPPORTED"]) then "LEANS_SUPPORTED"
      elsif value > BigDecimal(t["UNRESOLVED_ABOVE"]) then "UNRESOLVED"
      elsif value > BigDecimal(t["LEANS_CONTRADICTED_ABOVE"]) then "LEANS_CONTRADICTED"
      else "CONTRADICTED"
      end
    end

    # results: lets a caller that has already scored a set hand the scores in,
    # so a page listing many checks does not score each one separately.
    def call(claims, seq, model, results: nil)
      results = results ? claims.map { |c| results[c.id] }.compact : claims.map { |c| Scoring::Score.call(c, seq, model) }
      summarize(results, seq, model)
    end

    # The same reading for any set of scored claims: an investigation, or every
    # claim under a section of an outline (owner request, 2026-09-23), so the two
    # mean the same thing wherever they appear.
    def summarize(results, seq, model, collection: false)
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
      figure, stated, note = collection ? average(probabilities, checkable, seq, model) : together(probabilities, checkable, seq, model)
      badge = collection ? collection_badge(figure, checkable, model) : badge_for(states, results, checkable: checkable, against: against, holds: holds, open: open)
      { headline: headline, sentence: parts.join("; "), stated: stated, figure: figure, badge: badge,
        counts: { claims: states.size, checkable: checkable, against: against, holds: holds, open: open, not_checkable: not_checkable },
        note: note }
    end

    # One statement: the figure for every checkable claim holding at once,
    # treating them as independent. Only when every checkable claim has a
    # probability, since a product that skipped one would claim more than was
    # checked.
    def together(probabilities, checkable, seq, model)
      note = "The number is the model's figure for every checkable claim holding at once, treating them as independent."
      return [ nil, nil, note ] unless checkable.positive? && probabilities.size == checkable

      figure = Scoring::Decimal.fixed(probabilities.reduce(BigDecimal("1")) { |a, b| a * b }, 4)
      [ figure, "#{figure} under #{model.full_name} at snapshot #{seq} for all claims together", note ]
    end

    # A collection (an outline section): the average score of the claims that
    # have one, once at least half the checkable claims do. The product was
    # tried first and was wrong here twice over (2026-09-23): nearly every
    # section of a real outline holds one claim with too little evidence, so
    # almost none had a figure, and the few that did shrank with their size —
    # 0.0047 for a chapter whose claims mostly held.
    def average(probabilities, checkable, seq, model)
      note = "The average score of the claims under this section that have one. Model-conditional, not a share of truth, and never a score for the speaker."
      return [ nil, nil, note ] unless checkable.positive? && probabilities.any? && probabilities.size * 2 >= checkable

      figure = Scoring::Decimal.fixed(probabilities.sum / probabilities.size, 4)
      [ figure, "#{figure} under #{model.full_name} at snapshot #{seq}, the average of #{probabilities.size} of #{checkable} checkable claims' scores", note ]
    end

    # The hover text for a small badge: what it is, what it was read from, and
    # the figure if there is one. Article XVIII: a summary over many claims says
    # what it aggregates, and is a reading of those claims, not of whoever made
    # them.
    def title(summary, of:)
      label = Cards::Badge.for_key(summary[:badge])[:label]
      counts = summary[:counts]
      parts = [ "#{label}, read from the #{counts[:claims]} #{'claim'.pluralize(counts[:claims])} #{of}" ]
      parts << summary[:sentence] if summary[:sentence].present?
      parts << summary[:stated] if summary[:stated]
      "#{parts.join('. ')}. A reading of these claims, not of whoever made them; provisional until audited."
    end
  end
end
