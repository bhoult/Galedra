# SET_TRUTH_EVALUABLE as a windowed row (spec 02 §3.3, constitution P-3): the
# latest counted setting at S governs; the claim's creation value is the default.
class ClaimEvaluabilitySetting < ApplicationRecord
  include GraphProjection

  belongs_to :claim

  validates :not_evaluable_reason, inclusion: { in: Claim::NOT_EVALUABLE_REASONS }, if: -> { !truth_evaluable }
end
