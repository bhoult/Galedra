# A principal's grant of task permissions to an agent key (spec 02 §3.1, 05 §4).
# Projection: created by DELEGATE, ended by REVOKE_DELEGATION.
class AgentDelegation < ApplicationRecord
  include Projection

  belongs_to :principal, class_name: "Contributor", foreign_key: :principal_contributor_id, inverse_of: :delegations_as_principal
  belongs_to :delegate, class_name: "Contributor", foreign_key: :delegate_contributor_id, inverse_of: :delegations_as_delegate

  validates :delegation_signature, :valid_from, :valid_until, :created_seq, presence: true

  def revoked? = revoked_seq.present?

  def in_window?(at = Time.current)
    valid_from <= at && at <= valid_until
  end

  def usable?(at = Time.current)
    !revoked? && in_window?(at)
  end
end
