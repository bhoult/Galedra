# frozen_string_literal: true

# One turn in the exchange on a bug report or feature request. Outside the log,
# untrusted text, and never an input to anything epistemic.
class ReportMessage < ApplicationRecord
  MAX_CHARS = 2_000
  AUTHOR_KINDS = %w[assistant maintainer].freeze

  belongs_to :report, polymorphic: true
  belongs_to :assistant_token, optional: true
  belongs_to :user, optional: true

  validates :author_kind, inclusion: { in: AUTHOR_KINDS }
  validates :body, presence: true, length: { maximum: MAX_CHARS }
  # A verdict belongs to the reporter answering a maintainer. A maintainer
  # cannot mark their own answer satisfactory.
  validates :satisfied, absence: true, if: -> { author_kind == "maintainer" }

  scope :oldest_first, -> { order(:created_at) }

  def from_assistant? = author_kind == "assistant"
end
