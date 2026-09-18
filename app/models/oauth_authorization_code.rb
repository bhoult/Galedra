# A single-use authorization code (Stage 16), bound to the client, the
# redirect URI, the PKCE challenge, the scope, and the resource it was issued for.
class OauthAuthorizationCode < ApplicationRecord
  LIFETIME = 10.minutes

  belongs_to :oauth_client
  belongs_to :user

  def self.digest(code) = Digest::SHA256.hexdigest(code.to_s)

  def self.issue!(client:, user:, redirect_uri:, code_challenge:, scope:, resource:)
    code = "gac_#{SecureRandom.urlsafe_base64(32)}"
    create!(id: SecureRandom.uuid_v7, code_digest: digest(code), oauth_client: client, user: user, redirect_uri: redirect_uri,
            code_challenge: code_challenge, scope: scope, resource: resource, expires_at: LIFETIME.from_now)
    code
  end

  def usable? = used_at.nil? && expires_at > Time.current

  # RFC 7636 S256: BASE64URL(SHA256(verifier)) must equal the stored challenge.
  def verifier_matches?(verifier)
    return false if verifier.blank?

    expected = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    ActiveSupport::SecurityUtils.secure_compare(expected, code_challenge)
  end
end
