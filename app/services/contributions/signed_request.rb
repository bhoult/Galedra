# frozen_string_literal: true

module Contributions
  # Signed, non-logged API requests (leases, releases): a body with a protocol,
  # the signer's key id, an optional delegation, a timestamp within five
  # minutes, a payload, and an Ed25519 signature over the canonical body minus
  # the signature. Returns [contributor, delegation, payload].
  module SignedRequest
    MAX_SKEW = 5.minutes

    module_function

    def build(protocol:, payload:, key_pair:, delegation_id: nil, client_created_at: Time.now.utc)
      unsigned = { "protocol" => protocol, "signer_key_id" => key_pair.key_id, "delegation_id" => delegation_id,
                   "client_created_at" => client_created_at.utc.iso8601, "payload" => payload.as_json }.compact
      unsigned.merge("signature" => key_pair.sign(Crypto::CanonicalJson.call(unsigned)))
    end

    def verify!(body, protocol:)
      reject("SCHEMA_INVALID", "$", "expected a signed #{protocol} body") unless body.is_a?(Hash) && body["protocol"] == protocol &&
        body["payload"].is_a?(Hash) && body["signature"].is_a?(String)
      contributor = Contributor.find_by(key_id: body["signer_key_id"].to_s)
      reject("KEY_UNKNOWN", "$.signer_key_id", "no registered contributor has this key") if contributor.nil?
      reject("KEY_REVOKED", "$.signer_key_id", "revoked at seq #{contributor.revoked_seq}") if contributor.revoked?
      at = Time.iso8601(body["client_created_at"].to_s) rescue nil
      reject("SCHEMA_INVALID", "$.client_created_at", "expected RFC 3339 within #{MAX_SKEW.inspect} of now") if at.nil? || (at - Time.now.utc).abs > MAX_SKEW
      unless Crypto::Ed25519.verify(contributor.public_key, body["signature"], Crypto::CanonicalJson.call(body.except("signature")))
        reject("SIGNATURE_INVALID", "$.signature", "does not verify")
      end
      delegation = nil
      if body["delegation_id"]
        delegation = AgentDelegation.find_by(id: body["delegation_id"])
        reject("DELEGATION_INVALID", "$.delegation_id", "no such delegation for this key") if delegation.nil? || delegation.delegate_contributor_id != contributor.id
        reject("DELEGATION_REVOKED", "$.delegation_id", "revoked") if delegation.revoked?
        reject("DELEGATION_EXPIRED", "$.delegation_id", "outside valid_from..valid_until") unless delegation.in_window?
      end
      [ contributor, delegation, body["payload"] ]
    end

    def reject(code, path, detail)
      raise Ledger::Rejected.new([ { code: code, path: path, detail: detail } ])
    end
  end
end
