# frozen_string_literal: true

module Ledger
  # The server-side chain around each client envelope (spec 02 §1.2):
  #   entry_hash(n) = sha256(canonical({seq, prev_hash, envelope_hash, received_at}))
  module Entry
    TIMESTAMP_FORMAT = "%Y-%m-%dT%H:%M:%S.%6NZ"

    def self.timestamp(time)
      time.utc.strftime(TIMESTAMP_FORMAT)
    end

    def self.hash(seq:, prev_hash:, envelope_hash:, received_at:)
      Crypto::Hashing.json(
        "seq" => seq,
        "prev_hash" => prev_hash,
        "envelope_hash" => envelope_hash,
        "received_at" => timestamp(received_at)
      )
    end

    def self.sign(entry_hash)
      Crypto::SystemKey.key_pair.sign(entry_hash)
    end

    def self.server_signature_ok?(entry_hash, signature)
      Crypto::Ed25519.verify(Crypto::SystemKey.public_key, signature, entry_hash)
    end
  end
end
