# A signing identity: human, agent, or the system itself (spec 02 §3.1).
# Projection: rows are created by REGISTER_KEY and revoked by REVOKE_KEY
# through Ledger::Apply. Server-held key material lives in CustodiedKey.
class Contributor < ApplicationRecord
  include Projection

  HUMAN = "HUMAN"
  AGENT = "AGENT"
  SYSTEM = "SYSTEM"
  KINDS = [ HUMAN, AGENT, SYSTEM ].freeze

  # ANONYMOUS (Stage 12): a server-custodied key with no account. Weighted in audit
  # sampling, caps, and labels; never in claim scores (Art. XI).
  IDENTITY_TIERS = %w[ANONYMOUS PSEUDONYMOUS ESTABLISHED EXTERNALLY_VERIFIED INSTITUTIONAL].freeze
  MAX_HOME_URL = 200

  # A key's home node (Stage 23, spec 14 §5): an http(s) origin, no query, no fragment.
  def self.home_url?(value)
    return false unless value.is_a?(String) && value.length <= MAX_HOME_URL

    uri = URI.parse(value)
    uri.is_a?(URI::HTTP) && uri.host.present? && uri.query.nil? && uri.fragment.nil? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end

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
  # The node this key lives on; null on the row means this node.
  def home_node_url = Ledger::Node.home_url_for(self)
  def anonymous? = identity_tier == "ANONYMOUS"
  def adopted_by_key_id = metadata["adopted_by"]
  def adopted? = adopted_by_key_id.present?

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
