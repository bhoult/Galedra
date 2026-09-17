# A signing identity: human, agent, or the system itself (spec 02 §3.1).
# Rows are created by REGISTER_KEY contributions from Stage 2 onward.
class Contributor < ApplicationRecord
  HUMAN = "HUMAN"
  AGENT = "AGENT"
  SYSTEM = "SYSTEM"
  KINDS = [ HUMAN, AGENT, SYSTEM ].freeze

  IDENTITY_TIERS = %w[PSEUDONYMOUS ESTABLISHED EXTERNALLY_VERIFIED INSTITUTIONAL].freeze

  belongs_to :user, optional: true

  encrypts :encrypted_private_key

  validates :key_id, presence: true, uniqueness: true, format: { with: Crypto::Ed25519::KEY_ID_FORMAT }
  validates :public_key, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :identity_tier, inclusion: { in: IDENTITY_TIERS }
  validate :key_id_matches_public_key
  validate :system_key_is_never_custodied

  def server_custodied?
    encrypted_private_key.present?
  end

  private

  def key_id_matches_public_key
    return if public_key.blank? || key_id.blank?
    return if Crypto::Ed25519.key_id(public_key) == key_id

    errors.add(:key_id, "does not match the public key")
  rescue ArgumentError
    errors.add(:public_key, "is not valid base64url")
  end

  def system_key_is_never_custodied
    return unless kind == SYSTEM && encrypted_private_key.present?

    errors.add(:encrypted_private_key, "must be absent for the system key; it lives only in the environment")
  end
end
