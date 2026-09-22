# frozen_string_literal: true

module Assistants
  # What this connection has left hanging, told to it unprompted.
  #
  # A session ends and the next one begins knowing nothing. On 2026-09-22 one
  # ChatGPT session filed a bug report; a later session from the same account had
  # no idea it existed, so it could neither read the answer nor say whether it
  # settled anything. The node was never in doubt about who it was talking to —
  # every call carries an `AssistantToken`, and `filer_token_ids` already follows
  # a named token to its principal so a reconnection finds its own filings. What
  # was missing is that nobody told it.
  #
  # `docs/CONTEXT.md` records the other half of this from the maintainer's side:
  # an assistant filed fourteen reports in a day, could not read a single answer,
  # and kept filing the same ground. Three states are worth saying out loud, and
  # they are different obligations:
  #
  # - **answered** — a maintainer replied and it is the filer's turn. Unanswered,
  #   it settles itself after `Triageable::UNANSWERED_AFTER`, which is fine when
  #   the filer agrees and wrong when it does not.
  # - **held** — a maintainer agreed to work that is not done. Nothing is wanted
  #   from the filer; it is here so a later session can see whether it landed
  #   rather than refiling it.
  # - **open** — filed and not yet answered. Said as a count, because the useful
  #   thing to know is "you have already told them; do not tell them again".
  #
  # Anonymous connections are scoped to their own token by `filer_token_ids`: an
  # anonymous principal is not a stable identity, and treating it as one would
  # show one filer somebody else's reports.
  module Waiting
    module_function

    # nil when there is nothing, so a result carries the field only when it says
    # something. Two statements, both on an indexed column.
    def for(token)
      return nil if token.nil?

      ids = token.filer_token_ids
      return nil if ids.empty?

      bugs = by_state(BugReport, ids)
      features = by_state(FeatureRequest, ids)
      answered = bugs[:answered] + features[:answered]
      held = bugs[:held] + features[:held]
      open = bugs[:open] + features[:open]
      return nil if answered.empty? && held.empty? && open.zero?

      note(answered, held, open)
    end

    def by_state(model, ids)
      rows = model.where(assistant_token_id: ids, status: %w[OPEN ANSWERED]).pluck(:id, :status)
      return { answered: [], held: [], open: 0 } if rows.empty?

      answered_ids = rows.select { |_, status| status == "ANSWERED" }.map(&:first)
      held_ids = model.held.where(id: answered_ids).pluck(:id)
      { answered: answered_ids - held_ids, held: held_ids,
        open: rows.count { |_, status| status == "OPEN" } }
    end

    def note(answered, held, open)
      lines = []
      lines << "#{answered.size} you filed #{answered.size == 1 ? 'has' : 'have'} been answered and #{answered.size == 1 ? 'is' : 'are'} waiting on you: " \
               "read #{answered.size == 1 ? 'it' : 'them'} with get_report and reply with respond_to_report, saying whether the answer settles it. " \
               "An answer nobody comes back on closes itself, which is right when you agree and wrong when you do not." if answered.any?
      lines << "#{held.size} #{held.size == 1 ? 'is' : 'are'} held: a maintainer agreed to work that is not done yet. " \
               "Nothing is wanted from you; get_report says where it stands, so you need not file it again." if held.any?
      lines << "#{open} #{open == 1 ? 'is' : 'are'} filed and not yet answered. Do not file the same thing twice; " \
               "list_reports shows what you have already said." if open.positive?

      { answered: answered, held: held, open: open,
        note: "Reports you filed in this or an earlier session. #{lines.join(' ')}".squish }
    end
  end
end
