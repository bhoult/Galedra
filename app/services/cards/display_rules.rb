# frozen_string_literal: true

module Cards
  # The display rules of spec 06 §4 that more than one surface needs: the
  # labels beside a state (rules 4 and 6, and rule 5's caveat when a
  # directional state rests on almost no review), the review-check count
  # (rule 5: always a count, never a percentage or low/medium/high), and the
  # one form a probability may be written in (rule 2: never without its model
  # and snapshot). The answer card, the claim page, the share image, the API,
  # and the connector all read them here, so a change to a rule reaches every
  # surface at once instead of drifting between copies.
  module DisplayRules
    DIRECTIONAL_STATES = %w[SUPPORTED CONTRADICTED].freeze

    module_function

    def checks_done(checklist) = checklist.count { |_, v| v["ok"] }

    # Rule 5, in the form every surface shows: "2 of 4".
    def checks_count(checklist) = "#{checks_done(checklist)} of #{checklist.size}"

    # Rule 2. Nil when the state carries no number, so a caller can render the
    # "no probability" branch without repeating the condition.
    def stated(probability, model_name, seq)
      probability && "#{probability} under #{model_name} at snapshot #{seq}"
    end

    # anonymous (Stage 12) widens the provisional wording: a counted link whose
    # principal is anonymous and whose work no audit has confirmed.
    def labels(state:, provisional:, contested:, model_dependent:, review_checklist: {}, anonymous: false)
      out = []
      out << (anonymous ? "Not yet independently audited; some evidence was recorded by an anonymous contributor." : "Not yet independently audited.") if provisional
      out << "Evidence points both ways." if contested
      out << "This assessment depends heavily on modeling choices." if model_dependent
      checks = review_checklist.to_h
      done = checks_done(checks)
      if DIRECTIONAL_STATES.include?(state) && done <= 1
        out << "Evidence reviewed so far #{state == 'SUPPORTED' ? 'supports' : 'contradicts'} this claim, " \
               "but only #{done} of #{checks.size} review checks #{done == 1 ? 'has' : 'have'} been done."
      end
      out
    end

    # From a Scoring::Result.
    def for_result(result, anonymous: false)
      labels(state: result.assessment_state, provisional: result.provisional, contested: result.contested,
             model_dependent: result.model_dependent, review_checklist: result.review_checklist, anonymous: anonymous)
    end
  end
end
