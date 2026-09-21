# frozen_string_literal: true

module Settlements
  # A thread's rule: three distinct principals naming the same outcome.
  #
  # Not three tokens. Three tokens of one principal is self-certification, which
  # Invariant 9 forbids by contributor and by principal alike, and a node running
  # eleven sessions under one account would otherwise settle its own threads all
  # day. The consequence — that a node needs three connected people before a
  # thread can settle — is a matter of who is connected rather than a wall.
  #
  # Nothing is ever held here. A thread does not wait on one party, so there is
  # no party to be waiting on, and silence retires it rather than closing it.
  module Consensus
    module_function

    def held?(_row) = false
    def settles_at(_row) = nil

    def badge(row)
      case row.status
      when "OPEN" then open_badge(row)
      when "SETTLED" then settled_badge(row)
      when "RETIRED"
        [ "lapsed", "○", "retired", "Retired after #{DeterminationThread::RETIRE_AFTER.inspect} of silence. Nothing was agreed; any turn revives it." ]
      else
        [ "other", "·", row.status.downcase, row.status.downcase ]
      end
    end

    def open_badge(row)
      return [ "aside", "–", "stale", "Open, but what it hangs on is no longer current. Kept as history; it is not offered as work." ] unless row.subject_current?

      wanted = DeterminationThread::REQUIRED - (row.tally.values.max || 0)
      [ "needs-you", "●", "open", "Open. #{ActionController::Base.helpers.pluralize(wanted, 'more principal')} agreeing on one outcome settles it." ]
    end

    # The split, because three agreeing when two disagreed is a different fact
    # from three agreeing unopposed, and a reader weighing a settlement should
    # see which one they are looking at.
    def settled_badge(row)
      agreed, against = row.split
      word = row.outcome == "INVESTIGATE" ? "investigate" : "settled"
      [ "agreed", "✓", word,
        "Settled #{agreed}–#{against} as #{row.outcome.downcase.tr('_', ' ')}." ]
    end
  end
end
