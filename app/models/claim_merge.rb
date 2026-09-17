# MERGE_CLAIMS as a windowed row (spec 02 §3.3): from_claim is merged into
# into_claim while this row is counted; INVALIDATE the merge to reverse it.
class ClaimMerge < ApplicationRecord
  include GraphProjection

  belongs_to :from_claim, class_name: "Claim", inverse_of: :merges_from
  belongs_to :into_claim, class_name: "Claim", inverse_of: :merges_into
end
