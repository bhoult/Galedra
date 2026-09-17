# Cached score (spec 02 §3.5). A cache only: any row can be deleted and is
# recomputed byte-identically from the log and the model.
class ClaimScore < ApplicationRecord
  belongs_to :claim
  belongs_to :scoring_model
end
