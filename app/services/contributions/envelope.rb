# frozen_string_literal: true

module Contributions
  # Builds and inspects client envelopes (eir-contribution-v1). The signature
  # covers the canonical envelope minus the signature field (spec 05 §3).
  module Envelope
    def self.build(action_type:, payload:, key_pair:, delegation_id: nil, software: nil,
                   client_created_at: Time.now.utc, task_id: nil, task_packet_hash: nil)
      payload = payload.as_json
      unsigned = {
        "protocol" => Ledger::PROTOCOL,
        "action_type" => action_type,
        "signer_key_id" => key_pair.key_id,
        "delegation_id" => delegation_id,
        "task_id" => task_id,
        "task_packet_hash" => task_packet_hash,
        "client_created_at" => client_created_at.utc.iso8601,
        "software" => software&.as_json,
        "payload" => payload,
        "payload_hash" => Crypto::Hashing.json(payload)
      }.compact
      unsigned.merge("signature" => key_pair.sign(signed_bytes(unsigned)))
    end

    def self.signed_bytes(envelope)
      Crypto::CanonicalJson.call(envelope.except("signature"))
    end

    def self.hash(envelope)
      Crypto::Hashing.json(envelope)
    end

    def self.idempotency_key(signer_key_id:, task_id:, payload_hash:)
      Crypto::Hashing.bytes("#{signer_key_id}|#{task_id}|#{payload_hash}")
    end
  end
end
