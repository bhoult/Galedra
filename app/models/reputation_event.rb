# One audit's effect on one identity's task/domain reputation (spec 02 §3.4,
# 05 §7). Rolled up to the principal; nothing stores a mutable total.
class ReputationEvent < ApplicationRecord
  include Projection
  include ValidityWindow

  belongs_to :contribution
  belongs_to :contributor
  belongs_to :principal, class_name: "Contributor", foreign_key: :principal_contributor_id, optional: true, inverse_of: false
  belongs_to :audit
end
