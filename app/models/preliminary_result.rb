# An assistant's first reading of one claim (Stage 45), recorded by
# CREATE_PRELIMINARY_RESULT before any source was read into Galedra. It is an
# attributed contribution, not a verdict: it never reaches Scoring, a badge, a
# figure or a task packet, and it gives way to the claim's own state as soon as
# evidence moves it (Articles I, XIV, XIX).
class PreliminaryResult < ApplicationRecord
  include GraphProjection

  belongs_to :claim

  # Deliberately not the badge labels or the state names, so a first reading
  # can never be read as a score (owner, 2026-10-05).
  EXPECTATIONS = %w[EXPECTED_TO_HOLD EXPECTED_TO_HOLD_IN_PART EXPECTED_NOT_TO_HOLD NO_EXPECTATION].freeze
  MAX_RATIONALE = 600
  MAX_LEADS = 5
  MAX_LEAD_CHARS = 2_000
  MAX_MODEL_CHARS = 100

  WORDS = {
    "EXPECTED_TO_HOLD" => "expected to hold up",
    "EXPECTED_TO_HOLD_IN_PART" => "expected to hold up in part",
    "EXPECTED_NOT_TO_HOLD" => "expected not to hold up",
    "NO_EXPECTATION" => "no expectation either way"
  }.freeze

  validates :expectation, inclusion: { in: EXPECTATIONS }

  def words = WORDS.fetch(expectation)
end
