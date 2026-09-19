# A claim filed in a section (Stage 20). Projection of PLACE_CLAIM, or of
# CREATE_CLAIM carrying section_id. A claim may sit in several sections.
class ClaimPlacement < ApplicationRecord
  include GraphProjection

  belongs_to :claim
  belongs_to :section
end
