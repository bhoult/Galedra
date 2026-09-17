# frozen_string_literal: true

module Crypto
  # Who holds a contributor's private key (spec 05 §2). SELF: an API user or
  # agent signs client-side. SERVER: a browser user's key is generated here and
  # stored encrypted on the contributor row, unlocked only for that user's
  # authenticated session. SYSTEM: the ledger's own key (Crypto::SystemKey).
  module Custody
    SELF = "SELF"
    SERVER = "SERVER"
    SYSTEM = "SYSTEM"
    ALL = [ SELF, SERVER, SYSTEM ].freeze

    class NotAuthenticated < StandardError; end
    class NoServerKey < StandardError; end

    # Generates a server-custodied key for a browser user and returns the
    # contributor row holding it. Stage 2 routes this through REGISTER_KEY.
    def self.create_server_custodied(user:, display_name: nil, identity_tier: "PSEUDONYMOUS")
      pair = Ed25519::KeyPair.generate
      Contributor.create!(
        user: user,
        kind: Contributor::HUMAN,
        key_id: pair.key_id,
        public_key: pair.public_key,
        encrypted_private_key: pair.private_key,
        display_name: display_name,
        identity_tier: identity_tier
      )
    end

    # Unlocks the server-held key for an authenticated user. Returns an
    # Ed25519::KeyPair that can sign; never returns key material to callers.
    def self.signer_for(user)
      raise NotAuthenticated, "a signed-in user is required to unlock a server-held key" if user.nil?

      contributor = Contributor.where(user: user).where.not(encrypted_private_key: nil).first
      raise NoServerKey, "user #{user.id} has no server-custodied key" if contributor.nil?

      Ed25519::KeyPair.from_private_key(contributor.encrypted_private_key)
    end
  end
end
