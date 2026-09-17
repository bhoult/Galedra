# A signing identity: human, agent, or the system itself (spec 02 §3.1).
# Projection: rows are created by REGISTER_KEY and revoked by REVOKE_KEY
# through Ledger::Apply. Server-held key material lives in CustodiedKey.
class Contributor < ApplicationRecord
  include Projection

  HUMAN = "HUMAN"
  AGENT = "AGENT"
  SYSTEM = "SYSTEM"
  KINDS = [ HUMAN, AGENT, SYSTEM ].freeze

  IDENTITY_TIERS = %w[PSEUDONYMOUS ESTABLISHED EXTERNALLY_VERIFIED INSTITUTIONAL].freeze

  has_one :custodied_key, dependent: nil
  has_many :contributions, dependent: nil
  has_many :delegations_as_principal, class_name: "AgentDelegation",
           foreign_key: :principal_contributor_id, inverse_of: :principal, dependent: nil
  has_many :delegations_as_delegate, class_name: "AgentDelegation",
           foreign_key: :delegate_contributor_id, inverse_of: :delegate, dependent: nil

  validates :key_id, presence: true, uniqueness: true, format: { with: Crypto::Ed25519::KEY_ID_FORMAT }
  validates :public_key, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :identity_tier, inclusion: { in: IDENTITY_TIERS }
  validate :key_id_matches_public_key

  def human? = kind == HUMAN
  def agent? = kind == AGENT
  def system? = kind == SYSTEM

  def revoked? = revoked_seq.present?

  def server_custodied?
    custodied_key.present?
  end

  private

  def key_id_matches_public_key
    return if public_key.blank? || key_id.blank?
    return if Crypto::Ed25519.key_id(public_key) == key_id

    errors.add(:key_id, "does not match the public key")
  rescue ArgumentError
    errors.add(:public_key, "is not valid base64url")
  end
end
