# frozen_string_literal: true

module Settlements
  # The register's rule: the person who filed it decides when it is done.
  #
  # ANSWERED rather than DONE, because "a maintainer dealt with it" is not the
  # same as "the person who reported it agrees". CLOSED is reserved for the two
  # sides agreeing, and only a reporter's verdict reaches it — except by the
  # timeout below, and by a maintainer closing on behalf of a filer who has
  # nobody to ask.
  module Opener
    module_function

    # A reporter may simply never come back, and a report cannot wait on someone
    # who has gone. An answer that has stood this long without a word against it
    # is taken as settled; the reporter can still disagree afterwards and it
    # reopens, so this closes the waiting rather than the question.
    UNANSWERED_AFTER = 3.hours

    # Answered, and deliberately not settling: the last maintainer turn said so.
    # The timeout's licence was "if the reporter does not respond and *you think
    # it is settled*", and `answer!` could only say the first half until this
    # existed.
    def held?(row) = row.last_answer&.settles == false

    def settles_at(row)
      return nil unless row.status == "ANSWERED"
      return nil if held?(row)

      (row.last_answer_at || row.updated_at) + UNANSWERED_AFTER
    end

    def badge(row)
      case row.status
      when "OPEN"
        row.turns.any? ? [ "needs-you", "●", "you", "Reopened by the reporter. Waiting on a maintainer." ]
                       : [ "needs-you", "●", "you", "Filed. Waiting on a maintainer." ]
      when "ANSWERED"
        if held?(row)
          [ "held", "◐", "held", "Answered, and held open on purpose until the work it needs is done. It will not close itself." ]
        else
          [ "with-reporter", "○", "them", "Answered. Waiting on the reporter to say whether it settles it." ]
        end
      when "CLOSED"
        row.agreed? ? [ "agreed", "✓", "agreed", "Closed: the reporter said it was settled." ]
                    : [ "lapsed", "✓", "lapsed", "Closed with no reply from the reporter. It reopens if they disagree later." ]
      when "IGNORED"
        [ "aside", "–", "aside", "Set aside." ]
      else
        [ "other", "·", row.status.downcase, row.status.downcase ]
      end
    end
  end
end
