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

  included do
    validates :status, inclusion: { in: STATUSES }
    has_many :messages, class_name: "ReportMessage", as: :report, dependent: :destroy, inverse_of: :report

    scope :with_status, ->(value) { STATUSES.include?(value.to_s) ? where(status: value.to_s) : all }
    scope :newest_first, -> { order(created_at: :desc) }
  end

  def open? = status == "OPEN"

  # Waiting on the reporter rather than on us.
  def awaiting_reporter? = status == "ANSWERED"

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
