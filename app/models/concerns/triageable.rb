# frozen_string_literal: true

# A maintainer's working status for something a person or an assistant filed
# (bug reports and feature requests). Outside the log, mutable, and never an
# input to anything epistemic: marking a report done says the maintainer dealt
# with it, not that the thing reported was true or false.
module Triageable
  extend ActiveSupport::Concern

  # ANSWERED rather than DONE, because "a maintainer dealt with it" is not the
  # same as "the person who reported it agrees". CLOSED is reserved for the two
  # sides agreeing, and only a reporter's verdict can reach it (owner request,
  # 2026-09-20).
  STATUSES = %w[OPEN ANSWERED CLOSED IGNORED].freeze

  # A reporter may simply never come back, and a report cannot wait on someone
  # who has gone (owner request, 2026-09-20). An answer that has stood this long
  # without a word against it is taken as settled. Nothing is lost by it: the
  # reporter can still disagree afterwards and the report reopens, so this
  # closes the waiting rather than the question.
  UNANSWERED_AFTER = 3.hours

  included do
    validates :status, inclusion: { in: STATUSES }
    has_many :messages, class_name: "ReportMessage", as: :report, dependent: :destroy, inverse_of: :report

    scope :with_status, ->(value) { STATUSES.include?(value.to_s) ? where(status: value.to_s) : all }
    scope :newest_first, -> { order(created_at: :desc) }
  end

  def open? = status == "OPEN"

  # Waiting on the reporter rather than on us.
  def awaiting_reporter? = status == "ANSWERED"

  # The reporter said the answer settled it. Closing can also happen without
  # them — by timeout, or by a maintainer closing on behalf of a filer who has
  # nobody to ask — and a list that shows both as "closed" hides which.
  def agreed? = messages.any? { |m| m.from_assistant? && m.satisfied }

  # Whose turn it is. A status word does not say: "answered" read the same for a
  # report waiting on its filer and for one already settled. Said in three
  # widths, because the list column is a few characters wide and the full
  # sentence wrapped to four lines in it (owner request, 2026-09-20):
  # a key for styling, a mark and one word for the row, the sentence for the
  # tooltip and the report's own page.
  def state_badge
    case status
    when "OPEN"
      messages.any? ? [ "needs-you", "●", "you", "Reopened by the reporter. Waiting on a maintainer." ]
                    : [ "needs-you", "●", "you", "Filed. Waiting on a maintainer." ]
    when "ANSWERED"
      [ "with-reporter", "○", "them", "Answered. Waiting on the reporter to say whether it settles it." ]
    when "CLOSED"
      agreed? ? [ "agreed", "✓", "agreed", "Closed: the reporter said it was settled." ]
              : [ "lapsed", "✓", "lapsed", "Closed with no reply from the reporter. It reopens if they disagree later." ]
    when "IGNORED"
      [ "aside", "–", "aside", "Set aside." ]
    else
      [ "other", "·", status.downcase, status.downcase ]
    end
  end

  def state_line = state_badge.last

  # When silence will settle this, so the reporter can be told rather than
  # finding out afterwards.
  def settles_at
    return nil unless awaiting_reporter?

    (last_answer_at || updated_at) + UNANSWERED_AFTER
  end

  def last_answer_at = messages.where(author_kind: "maintainer").maximum(:created_at)

  class_methods do
    # Closes answers nobody has come back on. Idempotent, and it records the
    # reason as a turn so the page shows why it closed rather than appearing to
    # close itself.
    def settle_unanswered!(now: Time.current)
      where(status: "ANSWERED").find_each do |row|
        due = row.settles_at
        next if due.nil? || due > now

        row.transaction do
          row.messages.create!(author_kind: "maintainer", body: "Closed with no response after #{UNANSWERED_AFTER.inspect}. " \
                                                                "Say so with respond_to_report if this is not settled and it reopens.",
                               created_at: now)
          row.update!(status: "CLOSED")
        end
      end
    end
  end

  # A maintainer's turn. `resolution` keeps the latest answer so the existing
  # pages and the MCP read-back go on working unchanged; the message is the
  # record of who said what, when.
  def answer!(body:, user: nil, status: "ANSWERED")
    transaction do
      messages.create!(author_kind: "maintainer", user: user, body: body, created_at: Time.current) if body.present?
      update!(status: status, resolution: body.presence || resolution)
    end
  end

  # The reporter's turn. Satisfied closes it by agreement; unsatisfied reopens
  # it, with the reason attached rather than lost.
  def respond!(body:, satisfied:, token: nil, user: nil)
    transaction do
      messages.create!(author_kind: "assistant", assistant_token: token, user: user,
                       body: body, satisfied: satisfied, created_at: Time.current)
      update!(status: satisfied ? "CLOSED" : "OPEN")
    end
  end
end
