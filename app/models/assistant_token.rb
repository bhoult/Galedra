# A connected assistant (IMPLEMENTATION.md Stage 12): a bearer token that lets
# the server sign for a server-custodied AGENT key under a DELEGATE from the
# principal, who is either a signed-in user's key or an anonymous key with no
# account. The token is stored hashed and shown once. Not a projection.
class AssistantToken < ApplicationRecord
  PROVIDERS = %w[anthropic openai xai google other].freeze

  belongs_to :agent, class_name: "Contributor", foreign_key: :agent_contributor_id, inverse_of: false
  belongs_to :principal, class_name: "Contributor", foreign_key: :principal_contributor_id, inverse_of: false
  belongs_to :delegation, class_name: "AgentDelegation", inverse_of: false
  belongs_to :user, optional: true

  encrypts :adoption_code

  before_create :assign_adoption_code

  validates :token_digest, presence: true, uniqueness: true
  validates :hourly_cap, numericality: { only_integer: true, greater_than: 0 }

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  def self.find_by_token(token)
    return nil if token.blank?

    find_by(token_digest: digest(token))
  end

  def revoked? = revoked_at.present?
  def anonymous? = principal.identity_tier == "ANONYMOUS"

  # Usable only while its delegation is live, so revocation in the log wins.
  def usable?
    !revoked? && !delegation.revoked? && delegation.in_window? && !agent.revoked?
  end

  # A rolling hour rather than a calendar one: with a fixed boundary an agent
  # can spend a full cap at 10:59 and another at 11:01, so the window that is
  # meant to bound a runaway briefly allows twice the rate.
  def writes_this_hour
    Contribution.where(signer_key_id: agent.key_id).where.not(action_type: "REGISTER_KEY").where("received_at >= ?", 1.hour.ago).count
  end

  def over_hourly_cap? = writes_this_hour >= hourly_cap

  private

  def assign_adoption_code
    self.adoption_code ||= "adopt_#{SecureRandom.urlsafe_base64(18)}"
    self.adoption_digest ||= self.class.digest(adoption_code)
  end
end
