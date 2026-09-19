# One premise of an inference (Stage 25): a claim and whether the step needs
# it to hold or to fail.
class InferencePremise < ApplicationRecord
  include GraphProjection

  POLARITIES = %w[HOLDS FAILS].freeze

  belongs_to :inference
  belongs_to :claim

  validates :polarity, inclusion: { in: POLARITIES }
end
