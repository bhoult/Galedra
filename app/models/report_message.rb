# frozen_string_literal: true

# One turn in the exchange on a bug report or feature request. Outside the log,
# untrusted text, and never an input to anything epistemic.
class ReportMessage < ApplicationRecord
  # A turn is prose, not a form field: a reply that reasons through a diagnosis
  # runs longer than a bug report's `happened`. 2,000 rejected a 2,900-character
  # answer twice, as a bare 422 with nothing the filer could read
  # (docs/experiments/2026-09-20-second-connector-run.md).
  MAX_CHARS = 5_000
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
