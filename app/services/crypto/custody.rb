# frozen_string_literal: true

module Crypto
  # Who holds a contributor's private key (spec 05 §2). SELF: an API user or
  # agent signs client-side. SERVER: a browser user's key is generated here,
  # registered through the log like any other key, and stored encrypted in
  # CustodiedKey, unlocked only for that user's authenticated session. SYSTEM:
  # the ledger's own key (Crypto::SystemKey).
  module Custody
    SELF = "SELF"
    SERVER = "SERVER"
    SYSTEM = "SYSTEM"
    ALL = [ SELF, SERVER, SYSTEM ].freeze

    class NotAuthenticated < StandardError; end
    class NoServerKey < StandardError; end

    # Generates and registers a server-custodied key for a browser user.
    def self.create_server_custodied(user:, display_name: nil, identity_tier: "PSEUDONYMOUS")
      pair = Ed25519::KeyPair.generate
      envelope = Contributions::Envelope.build(
        action_type: "REGISTER_KEY",
        payload: { "public_key" => pair.public_key, "kind" => Contributor::HUMAN,
                   "display_name" => display_name, "identity_tier" => identity_tier }.compact,
        key_pair: pair
      )
      CustodiedKey.transaction do
        Ledger::Append.call(envelope, custody: SERVER)
        contributor = Contributor.find_by!(key_id: pair.key_id)
        CustodiedKey.create!(contributor: contributor, user: user, encrypted_private_key: pair.private_key)
        contributor
      end
    end

    # Unlocks the server-held key for an authenticated user. Returns an
    # Ed25519::KeyPair that can sign; never hands key material to callers.
    def self.signer_for(user)
      raise NotAuthenticated, "a signed-in user is required to unlock a server-held key" if user.nil?

      custodied = CustodiedKey.find_by(user: user)
      raise NoServerKey, "user #{user.id} has no server-custodied key" if custodied.nil?

      Ed25519::KeyPair.from_private_key(custodied.encrypted_private_key)
    end
  end
end
