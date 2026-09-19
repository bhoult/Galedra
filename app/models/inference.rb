# A recorded reasoning step (Stage 25): premises with a polarity, a
# conclusion, the stated rule, a type, and a self-assessed strength. Never
# evidence: no released model gives it weight. Displayed, reviewed by task,
# and counted through the DERIVED_FROM edges recorded with it.
class Inference < ApplicationRecord
  include GraphProjection

  TYPES = %w[DEDUCTIVE INDUCTIVE ABDUCTIVE STATISTICAL ANALOGICAL CAUSAL DEFINITIONAL].freeze
  STRENGTHS = %w[ENTAILS STRONGLY_SUPPORTS SUPPORTS WEAKLY_SUPPORTS].freeze
  MIN_PREMISES = 2
  MAX_PREMISES = 12
  MAX_RULE = 500
  NOTE = "An inference is interpretation, not evidence: it never changes the assessment of its conclusion. Each premise is a claim with its own evidence."

  belongs_to :conclusion, class_name: "Claim", foreign_key: :conclusion_claim_id, inverse_of: false
  has_many :premises, class_name: "InferencePremise", dependent: nil

  validates :inference_type, inclusion: { in: TYPES }
  validates :strength, inclusion: { in: STRENGTHS }
  validates :rule, length: { maximum: MAX_RULE }, allow_nil: true

  def redacted? = redacted_by_seq.present?
end
