# frozen_string_literal: true

module Admin
  # Moderator-only API calls (spec 06 §2 admin endpoints) are signed bodies:
  # {"protocol":"eir-admin-v1","signer_key_id","client_created_at","payload","signature"},
  # signed over the canonical body minus the signature. Not log entries.
  module Request
    PROTOCOL = "eir-admin-v1"
    MAX_SKEW = 5.minutes

    module_function

    def build(payload:, key_pair:, client_created_at: Time.now.utc)
      unsigned = { "protocol" => PROTOCOL, "signer_key_id" => key_pair.key_id, "client_created_at" => client_created_at.utc.iso8601, "payload" => payload.as_json }
      unsigned.merge("signature" => key_pair.sign(Crypto::CanonicalJson.call(unsigned)))
    end

    # Returns the verified payload or raises Ledger::Rejected.
    def verify!(body)
      reject("SCHEMA_INVALID", "$", "expected a signed #{PROTOCOL} body") unless body.is_a?(Hash) && body["protocol"] == PROTOCOL &&
        body["payload"].is_a?(Hash) && body["signature"].is_a?(String)
      contributor = Contributor.find_by(key_id: body["signer_key_id"].to_s)
      reject("KEY_UNKNOWN", "$.signer_key_id", "no registered contributor has this key") if contributor.nil?
      reject("NOT_AUTHORIZED", "$.signer_key_id", "only a moderator key may call admin endpoints") unless Governance::Moderators.moderator?(contributor)
      at = Time.iso8601(body["client_created_at"].to_s) rescue nil
      reject("SCHEMA_INVALID", "$.client_created_at", "expected RFC 3339 within #{MAX_SKEW.inspect} of now") if at.nil? || (at - Time.now.utc).abs > MAX_SKEW
      unless Crypto::Ed25519.verify(contributor.public_key, body["signature"], Crypto::CanonicalJson.call(body.except("signature")))
        reject("SIGNATURE_INVALID", "$.signature", "does not verify")
      end
      body["payload"]
    end

    def reject(code, path, detail)
      raise Ledger::Rejected.new([ { code: code, path: path, detail: detail } ])
    end
  end
end
