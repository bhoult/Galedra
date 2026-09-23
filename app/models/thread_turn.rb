# frozen_string_literal: true

# One turn in any conversation here: a bug report, a feature request, or a thread
# on a determination (Stage 37). Outside the log, untrusted text, and never an
# input to anything epistemic.
#
# One table for all of them on purpose. A second implementation of a
# conversation would drift, and the drift is not hypothetical: a guidance line
# and a refusal hint said different things about when to file a report, and the
# narrower one won because it was the one being read.
class ThreadTurn < ApplicationRecord
  # A turn is prose, not a form field: a reply that reasons through a diagnosis
  # runs longer than a bug report's `happened`. 2,000 rejected a 2,900-character
  # answer twice, as a bare 422 with nothing the filer could read
  # (docs/experiments/2026-09-20-second-connector-run.md).
  MAX_CHARS = 5_000
  AUTHOR_KINDS = %w[assistant maintainer].freeze

  belongs_to :thread, polymorphic: true
  belongs_to :assistant_token, optional: true
  belongs_to :user, optional: true

  validates :author_kind, inclusion: { in: AUTHOR_KINDS }
  validates :body, presence: true, length: { maximum: MAX_CHARS }
  # `satisfied` belongs to the reporter answering a maintainer, and a maintainer
  # cannot mark their own answer satisfactory. `verdict` is the other question
  # entirely — the named outcome three principals must agree on in a thread — and
  # keeping them apart is why there are two columns and not one overloaded one.
  validates :satisfied, absence: true, if: -> { author_kind == "maintainer" }
  validates :verdict, inclusion: { in: DeterminationThread::OUTCOMES }, allow_nil: true
  # Stage 42 §9: where a fix is and the call that shows it, as fields a filer
  # can act on rather than prose it has to parse. A maintainer's to give, since
  # they are a claim about this repository.
  validates :fixed_in, length: { maximum: 100 }, absence: { if: -> { author_kind != "maintainer" } }
  validates :repro, length: { maximum: MAX_CHARS }, absence: { if: -> { author_kind != "maintainer" } }

  scope :oldest_first, -> { order(:created_at) }

  def from_assistant? = author_kind == "assistant"

  # The person behind the turn, whoever typed it. A person writing directly and
  # that person's assistant writing on their behalf are the same principal and
  # must never count twice toward a consensus.
  def principal_id = assistant_token&.principal_contributor_id || user&.contributor&.id
end
