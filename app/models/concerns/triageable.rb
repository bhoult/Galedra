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

  # HELD is not a stored status and must not become one: it is ANSWERED with the
  # last maintainer turn marked as not settling, which is a fact about the
  # thread rather than a fourth thing a report can be. It is a view, because
  # "answered and waiting on the reporter" and "answered and waiting on a stage
  # nobody has built" are different queues to work, and a list that shows them
  # as one is the same fault as a count of everyone's work read as a count of
  # yours. The lists carve HELD out of ANSWERED, so the two still sum.
  VIEWS = %w[OPEN ANSWERED HELD CLOSED IGNORED].freeze

  # Kept as the register's own name for it; the rule itself lives in the
  # settlement object, with everything else about who closes a report.
  UNANSWERED_AFTER = Settlements::Opener::UNANSWERED_AFTER

  included do
    include Threadable
    settles_by Settlements::Opener
    validates :status, inclusion: { in: STATUSES }

    # ANSWERED, with the last maintainer turn marked as not settling.
    scope :held, -> {
      where(status: "ANSWERED").where(
        "EXISTS (SELECT 1 FROM thread_turns m WHERE m.thread_type = :t AND m.thread_id = #{table_name}.id " \
        "AND m.author_kind = 'maintainer' AND m.settles = FALSE AND m.created_at = " \
        "(SELECT MAX(m2.created_at) FROM thread_turns m2 WHERE m2.thread_type = :t AND m2.thread_id = #{table_name}.id AND m2.author_kind = 'maintainer'))", t: name
      )
    }
    scope :with_status, lambda { |value|
      case value.to_s
      when "HELD" then held
      when "ANSWERED" then where(status: "ANSWERED").where.not(id: held.select(:id))
      when *STATUSES then where(status: value.to_s)
      else all
      end
    }
    scope :newest_first, -> { order(created_at: :desc) }
  end

  def open? = status == "OPEN"

  # Waiting on the reporter rather than on us.
  def awaiting_reporter? = status == "ANSWERED"

  # The reporter said the answer settled it. Closing can also happen without
  # them — by timeout, or by a maintainer closing on behalf of a filer who has
  # nobody to ask — and a list that shows both as "closed" hides which.
  def agreed? = turns.any? { |m| m.from_assistant? && m.satisfied }

  def last_answer_at = turns.where(author_kind: "maintainer").maximum(:created_at)

  def last_answer = turns.where(author_kind: "maintainer").order(:created_at).last

  class_methods do
    # Closes answers nobody has come back on. Idempotent, and it records the
    # reason as a turn so the page shows why it closed rather than appearing to
    # close itself.
    def settle_unanswered!(now: Time.current)
      where(status: "ANSWERED").find_each do |row|
        due = row.settles_at
        next if due.nil? || due > now

        row.transaction do
          row.add_turn!(author_kind: "maintainer", body: "Closed with no response after #{UNANSWERED_AFTER.inspect}. " \
                                                         "Say so with respond_to_report if this is not settled and it reopens.")
          row.update!(status: "CLOSED")
        end
      end
    end
  end

  # A maintainer's turn. `resolution` keeps the latest answer so the existing
  # pages and the MCP read-back go on working unchanged; the message is the
  # record of who said what, when.
  # `settles: false` is an answer that is not a resolution: work has been agreed
  # and not done yet. It still hands the report back, and it does not start the
  # timeout, because the timeout's licence is "if you think it is settled".
  def answer!(body:, user: nil, status: "ANSWERED", settles: true)
    transaction do
      add_turn!(body: body, author_kind: "maintainer", user: user, settles: settles) if body.present?
      update!(status: status, resolution: body.presence || resolution)
    end
  end

  # The reporter's turn. Satisfied closes it by agreement; unsatisfied reopens
  # it, with the reason attached rather than lost.
  # Returns whether the body had to be clipped, so the caller is told rather than
  # finding out later. Clipped, never refused: a turn that was too long used to
  # raise, and the filer got a bare 422 with nothing to read and no way to know
  # a shorter reply would land.
  def respond!(body:, satisfied:, token: nil, user: nil)
    text = body.to_s.strip
    clipped = text.length > ThreadTurn::MAX_CHARS
    transaction do
      add_turn!(body: text, author_kind: "assistant", token: token, user: user, satisfied: satisfied)
      update!(status: satisfied ? "CLOSED" : "OPEN")
    end
    clipped
  end
end
