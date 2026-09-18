# A registered OAuth client (Stage 16): a connector such as ChatGPT or
# Claude.ai, usually registered dynamically (RFC 7591). Public clients use
# PKCE and no secret; confidential ones present a secret at the token endpoint.
class OauthClient < ApplicationRecord
  AUTH_METHODS = %w[none client_secret_post client_secret_basic].freeze

  has_many :authorization_codes, class_name: "OauthAuthorizationCode", dependent: :delete_all
  has_many :tokens, class_name: "OauthToken", dependent: :delete_all

  validates :client_id, :name, presence: true
  validates :client_id, uniqueness: true
  validates :token_endpoint_auth_method, inclusion: { in: AUTH_METHODS }
  validate :redirect_uris_are_https_or_loopback

  def self.digest(secret) = Digest::SHA256.hexdigest(secret.to_s)

  def public? = token_endpoint_auth_method == "none"
  def secret_matches?(secret) = client_secret_digest.present? && ActiveSupport::SecurityUtils.secure_compare(client_secret_digest, self.class.digest(secret))
  # Exact match, except that loopback redirects (RFC 8252 §7.3, and Claude
  # Code's localhost form) match with the port ignored, since the port is
  # chosen per session.
  def redirect_uri_allowed?(uri)
    return true if redirect_uris.include?(uri.to_s)

    given = URI.parse(uri.to_s) rescue nil
    return false unless given.is_a?(URI::HTTP) && LOOPBACK.include?(given.host)

    redirect_uris.any? do |registered|
      r = URI.parse(registered) rescue nil
      r.is_a?(URI::HTTP) && LOOPBACK.include?(r.host) && r.scheme == given.scheme && r.host == given.host && r.path == given.path
    end
  end

  LOOPBACK = %w[localhost 127.0.0.1 ::1].freeze

  # Which assistant provider a connector name maps to, for the software field.
  def provider
    case name.downcase
    when /chatgpt|openai/ then "openai"
    when /claude|anthropic/ then "anthropic"
    when /gemini|google/ then "google"
    when /grok|xai/ then "xai"
    else "other"
    end
  end

  private

  def redirect_uris_are_https_or_loopback
    errors.add(:redirect_uris, "must not be empty") if redirect_uris.blank?
    redirect_uris.each do |uri|
      parsed = URI.parse(uri) rescue nil
      ok = parsed.is_a?(URI::HTTPS) || (parsed.is_a?(URI::HTTP) && LOOPBACK.include?(parsed.host)) || parsed&.scheme.to_s.match?(/\A[a-z][a-z0-9+.-]*\z/i) && !parsed.is_a?(URI::HTTP)
      errors.add(:redirect_uris, "#{uri} must be https, a loopback http address, or a custom scheme") unless ok && parsed.fragment.nil?
    end
  end
end
