# An independent evaluation of a prior contribution (spec 02 §3.4, 05 §9);
# itself a contribution and itself auditable (RE_AUDIT). The latest active
# audit on a target governs its effect.
class Audit < ApplicationRecord
  include Projection
  include ValidityWindow

  TYPES = %w[SOURCE_CHECK SCHEMA_CHECK INDEPENDENCE_CHECK RE_AUDIT].freeze
  RESULTS = %w[CONFIRMED MINOR_ERROR SUBSTANTIVE_ERROR FABRICATION UNRESOLVED].freeze
  DISAGREEING = %w[SUBSTANTIVE_ERROR FABRICATION].freeze

  belongs_to :contribution
  belongs_to :target_contribution, class_name: "Contribution"
  belongs_to :auditor, class_name: "Contributor", foreign_key: :auditor_contributor_id, inverse_of: false

  validates :audit_type, inclusion: { in: TYPES }
  validates :result, inclusion: { in: RESULTS }

  def re_audit? = audit_type == "RE_AUDIT"
  def disagrees? = DISAGREEING.include?(result)
end
