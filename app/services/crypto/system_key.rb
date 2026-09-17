# frozen_string_literal: true

module Crypto
  # The ledger's own Ed25519 key. It lives only in the environment, never in the
  # database (spec 05 §2), and its public half is published by /api/v1/meta.
  module SystemKey
    PRIVATE_ENV = "LEDGER_SYSTEM_PRIVATE_KEY"
    PUBLIC_ENV = "LEDGER_SYSTEM_PUBLIC_KEY"

    class Missing < StandardError; end
    class Mismatch < StandardError; end

    def self.configured?
      ENV[PRIVATE_ENV].present?
    end

    def self.key_pair
      raise Missing, "#{PRIVATE_ENV} is not set; run bin/rails ledger:keygen" unless configured?

      pair = Ed25519::KeyPair.from_private_key(ENV.fetch(PRIVATE_ENV))
      pinned = ENV[PUBLIC_ENV].presence
      if pinned && pinned != pair.public_key
        raise Mismatch, "#{PUBLIC_ENV} does not match the public half of #{PRIVATE_ENV}"
      end
      pair
    end

    def self.public_key = key_pair.public_key
    def self.key_id = key_pair.key_id
  end
end
