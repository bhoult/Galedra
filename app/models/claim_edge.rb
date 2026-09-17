# A typed relationship between claims (spec 02 §3.3). Stored and displayed;
# no probability propagation in v0.1.
class ClaimEdge < ApplicationRecord
  include GraphProjection

  TYPES = %w[SUPPORTS CONTRADICTS QUALIFIES REQUIRES DERIVED_FROM SAME_AS NARROWS BROADENS ALTERNATIVE_TO PREDICTS EXPLAINS].freeze

  belongs_to :from_claim, class_name: "Claim", inverse_of: :outgoing_edges
  belongs_to :to_claim, class_name: "Claim", inverse_of: :incoming_edges

  validates :relationship_type, inclusion: { in: TYPES }
end
