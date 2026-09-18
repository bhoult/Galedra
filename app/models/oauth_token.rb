# An access or refresh token (Stage 16), stored as a digest, mapped onto the
# durable AssistantToken that holds the person's delegation to this connector.
# Refresh tokens rotate; a replayed refresh token revokes its whole family.
class OauthToken < ApplicationRecord
  # Owner decision: tokens do not expire. Revocation (disconnecting the
  # assistant, or a replayed refresh token) is the only way they end.
  ACCESS_LIFETIME = nil
  REFRESH_LIFETIME = nil
  KINDS = %w[access refresh].freeze

  belongs_to :oauth_client
  belongs_to :assistant_token

  validates :kind, inclusion: { in: KINDS }

  def self.digest(token) = Digest::SHA256.hexdigest(token.to_s)

  def self.find_usable(kind, token)
    return nil if token.blank?

    record = find_by(kind: kind, token_digest: digest(token))
    record&.usable? ? record : nil
  end

  # Issues an access and refresh pair in one family. Returns [access, refresh] plaintexts.
  def self.issue_pair!(client:, assistant_token:, scope:, family_id: SecureRandom.uuid)
    access = "gat_#{SecureRandom.urlsafe_base64(32)}"
    refresh = "grt_#{SecureRandom.urlsafe_base64(32)}"
    create!(id: SecureRandom.uuid_v7, kind: "access", token_digest: digest(access), family_id: family_id, oauth_client: client, assistant_token: assistant_token, scope: scope, expires_at: ACCESS_LIFETIME&.from_now)
    create!(id: SecureRandom.uuid_v7, kind: "refresh", token_digest: digest(refresh), family_id: family_id, oauth_client: client, assistant_token: assistant_token, scope: scope, expires_at: REFRESH_LIFETIME&.from_now)
    [ access, refresh ]
  end

  def usable? = revoked_at.nil? && used_at.nil? && (expires_at.nil? || expires_at > Time.current) && assistant_token.usable?
  def read_only? = scope.to_s.split.exclude?("galedra")

  def revoke_family!
    self.class.where(family_id: family_id, revoked_at: nil).update_all(revoked_at: Time.current)
  end
end
