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
  validates :daily_cap, numericality: { only_integer: true, greater_than: 0 }

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

  def writes_today
    Contribution.where(signer_key_id: agent.key_id).where.not(action_type: "REGISTER_KEY").where("received_at >= ?", Time.current.beginning_of_day).count
  end

  def over_daily_cap? = writes_today >= daily_cap

  private

  def assign_adoption_code
    self.adoption_code ||= "adopt_#{SecureRandom.urlsafe_base64(18)}"
    self.adoption_digest ||= self.class.digest(adoption_code)
  end
end
