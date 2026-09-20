# frozen_string_literal: true

# How much one assistant may file in a day. The cap is a guard against a loop
# filing the same thing a thousand times, not a budget for a working day, and it
# was being spent as though it were one: a named assistant working a real outline
# for eighteen hours filed ten bug reports and ten feature requests — nearly all
# of them findings that turned into fixes — and then could file nothing at all
# (docs/experiments/2026-09-20-second-connector-run.md).
#
# So an accountable filer gets room. A named token belongs to a person, through a
# delegation, and is answerable; an anonymous one is not, and keeps the tight
# cap. Neither can flood, because a repeat of the same text inside the window is
# counted rather than stored, so a loop filing one thing over and over uses one
# row however often it runs.
#
# Responding to a report is never capped. That is the channel that *reduces*
# filings, and capping it produces the duplication it exists to prevent.
module FilingCap
  extend ActiveSupport::Concern

  ANONYMOUS_DAILY_CAP = 10
  NAMED_DAILY_CAP = 60

  class_methods do
    def cap_for(token) = token&.anonymous? == false ? NAMED_DAILY_CAP : ANONYMOUS_DAILY_CAP

    # Counted per filer, not per token, or reconnecting would reset the day's
    # count — which it did.
    def filed_today(token)
      return 0 if token.nil?

      where(assistant_token_id: token.filer_token_ids).where("created_at >= ?", Time.current.beginning_of_day).count
    end

    # A refusal a filer can act on: what it has spent, what the limit is, when it
    # resets, and what to do instead. The old one said only "at most 10 a day",
    # so an assistant that hit it could not tell whether it had filed ten or
    # whether something else was counting against it, and guessed wrong.
    def refuse_if_over_cap!(token, noun)
      cap = cap_for(token)
      used = filed_today(token)
      return if used < cap

      resets = Time.current.tomorrow.beginning_of_day
      raise Ledger::Rejected.new([ { code: "RATE_LIMITED", path: "$",
                                     detail: "#{used} of #{cap} #{noun} filed today by this assistant; the count resets at " \
                                             "#{resets.utc.iso8601}. Bug reports and feature requests are counted separately. " \
                                             "Answering a report you already filed is never capped: use respond_to_report, " \
                                             "which is also the right place for anything that corrects or adds to one." } ])
    end
  end
end
