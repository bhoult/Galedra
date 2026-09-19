# frozen_string_literal: true

module Snapshots
  # A signed checkpoint (spec 14 §7): the node's statement that at seq N the
  # chain head was H, following its previous checkpoint. Any holder of the
  # node's public key can verify it without trusting the transport. Signed
  # over canonical JSON with the system key, like every log entry.
  module Checkpoint
    module_function

    def build(seq:, entry_hash:, previous_seq:, created_at:)
      unsigned = {
        "protocol" => Ledger::Node::CHECKPOINT_PROTOCOL,
        "node_url" => Ledger::Node.url,
        "node_key_id" => Crypto::SystemKey.key_id,
        "seq" => seq,
        "entry_hash" => entry_hash,
        "previous_checkpoint_seq" => previous_seq,
        "created_at" => Ledger::Entry.timestamp(created_at)
      }
      unsigned.merge("signature" => Crypto::SystemKey.key_pair.sign(signed_bytes(unsigned)))
    end

    def signed_bytes(checkpoint)
      Crypto::CanonicalJson.call(checkpoint.except("signature"))
    end

    def verify(checkpoint, public_key: Crypto::SystemKey.public_key)
      return false unless checkpoint.is_a?(Hash) && checkpoint["signature"].is_a?(String)

      Crypto::Ed25519.verify(public_key, checkpoint["signature"], signed_bytes(checkpoint))
    rescue ArgumentError
      false
    end
  end
end
