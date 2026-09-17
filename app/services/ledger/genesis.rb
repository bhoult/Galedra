# frozen_string_literal: true

module Ledger
  # seq 0: the system key registering itself (spec 02 §1.2a).
  module Genesis
    def self.ensure!
      existing = Contribution.find_by(seq: 0)
      if existing
        verify!(existing)
        return existing
      end

      pair = Crypto::SystemKey.key_pair
      envelope = Contributions::Envelope.build(
        action_type: "REGISTER_KEY",
        payload: { "public_key" => pair.public_key, "kind" => Contributor::SYSTEM, "display_name" => "System" },
        key_pair: pair
      )
      Append.call(envelope, custody: Crypto::Custody::SYSTEM).contribution
    end

    # The pinned deployment key must be the one registered at seq 0.
    def self.verify!(genesis)
      ok = genesis.seq.zero? && genesis.action_type == "REGISTER_KEY" &&
           genesis.custody == Crypto::Custody::SYSTEM &&
           genesis.payload&.dig("public_key") == Crypto::SystemKey.public_key
      return true if ok

      raise GenesisMismatch, "seq 0 registers #{genesis.signer_key_id}, but the configured system key is #{Crypto::SystemKey.key_id}"
    end
  end
end
