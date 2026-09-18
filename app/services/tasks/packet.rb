# frozen_string_literal: true

module Tasks
  # Server-signed task packets (spec 04 §3): the hash is over the canonical
  # packet without server_signature, and the system key signs that hash.
  module Packet
    PROTOCOL = "eir-task-v1"
    RESULT_PROTOCOL = "eir-result-v1"

    module_function

    def hash(packet)
      Crypto::Hashing.json(packet.except("server_signature"))
    end

    def sign(packet)
      unsigned = packet.except("server_signature")
      unsigned.merge("server_signature" => Crypto::SystemKey.key_pair.sign(hash(unsigned)))
    end

    def signature_ok?(packet, public_key = Crypto::SystemKey.public_key)
      Crypto::Ed25519.verify(public_key, packet["server_signature"].to_s, hash(packet))
    end
  end
end
