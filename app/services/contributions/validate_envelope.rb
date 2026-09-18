# frozen_string_literal: true

module Contributions
  # Checks everything about an envelope that does not depend on log position:
  # shape, closed enums, hashes, signer resolution, signature, delegation.
  # Raises Ledger::Rejected with machine-readable errors (spec 06 §1); nothing
  # is logged on failure (04 §6).
  class ValidateEnvelope
    REQUIRED = %w[protocol action_type signer_key_id client_created_at payload payload_hash signature].freeze
    OPTIONAL = %w[delegation_id task_id task_packet_hash software].freeze
    RESULT_PROTOCOL = "eir-result-v1"
    UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
    SELF_SIGNED_ACTIONS = %w[REGISTER_KEY REVOKE_KEY].freeze

    Result = Struct.new(:envelope, :action_type, :action_class, :signer_key_id, :public_key, :contributor,
                        :delegation, :payload, :payload_hash, :envelope_hash, :idempotency_key, keyword_init: true)

    def self.call(envelope) = new(envelope).call

    def initialize(envelope)
      @envelope = envelope
    end

    def call
      shape!
      no_floats!
      payload_hash!
      resolve_signer!
      signature!
      delegation!

      Result.new(
        envelope: @envelope, action_type: action_type, action_class: Ledger::ActionTypes.class_for(action_type),
        signer_key_id: signer_key_id, public_key: @public_key, contributor: @contributor,
        delegation: @delegation, payload: @envelope["payload"], payload_hash: @envelope["payload_hash"],
        envelope_hash: Envelope.hash(@envelope),
        idempotency_key: Envelope.idempotency_key(signer_key_id: signer_key_id,
                                                  task_id: @envelope["task_id"], payload_hash: @envelope["payload_hash"])
      )
    end

    private

    def action_type = @envelope["action_type"]

    # Result envelopes (04 §4) name the signer contributor_key_id; the log column is signer_key_id.
    def signer_key_id = @envelope["signer_key_id"] || @envelope["contributor_key_id"]

    def result_envelope? = @envelope.is_a?(Hash) && @envelope["protocol"] == RESULT_PROTOCOL

    def reject(code, path, detail)
      raise Ledger::Rejected.new([ { code: code, path: path, detail: detail } ])
    end

    def shape!
      reject("SCHEMA_INVALID", "$", "envelope must be a JSON object") unless @envelope.is_a?(Hash)
      return result_shape! if result_envelope?

      reject("SCHEMA_INVALID", "$.protocol", "TASK_RESULT uses #{RESULT_PROTOCOL}") if action_type == "TASK_RESULT"
      unknown = @envelope.keys - REQUIRED - OPTIONAL
      reject("SCHEMA_INVALID", "$", "unknown fields: #{unknown.join(', ')}") if unknown.any?
      missing = REQUIRED - @envelope.keys
      reject("SCHEMA_INVALID", "$", "missing fields: #{missing.join(', ')}") if missing.any?
      reject("SCHEMA_INVALID", "$.protocol", "expected #{Ledger::PROTOCOL}") unless @envelope["protocol"] == Ledger::PROTOCOL
      reject("UNKNOWN_ACTION_TYPE", "$.action_type", "not in the closed list") unless Ledger::ActionTypes::ALL.include?(action_type)
      reject("UNSUPPORTED_ACTION", "$.action_type", "not handled by this server yet") unless Ledger::ActionTypes.supported?(action_type)
      reject("SCHEMA_INVALID", "$.signer_key_id", "expected ed25519:<sha256 hex>") unless Crypto::Ed25519::KEY_ID_FORMAT.match?(@envelope["signer_key_id"].to_s)
      reject("SCHEMA_INVALID", "$.client_created_at", "expected RFC 3339") unless rfc3339?(@envelope["client_created_at"])
      reject("SCHEMA_INVALID", "$.payload", "must be a JSON object") unless @envelope["payload"].is_a?(Hash)
      reject("SCHEMA_INVALID", "$.payload_hash", "expected sha256:<hex>") unless Crypto::Hashing.valid?(@envelope["payload_hash"])
      reject("SCHEMA_INVALID", "$.signature", "must be a non-empty string") unless @envelope["signature"].is_a?(String) && @envelope["signature"].present?
      reject("SCHEMA_INVALID", "$.delegation_id", "expected a UUID or null") unless nullable(@envelope["delegation_id"]) { |v| v.is_a?(String) && UUID.match?(v) }
      reject("SCHEMA_INVALID", "$.task_id", "expected a UUID or null") unless nullable(@envelope["task_id"]) { |v| v.is_a?(String) && UUID.match?(v) }
      reject("SCHEMA_INVALID", "$.task_packet_hash", "expected sha256:<hex> or null") unless nullable(@envelope["task_packet_hash"]) { |v| Crypto::Hashing.valid?(v) }
      reject("SCHEMA_INVALID", "$.software", "expected an object or null") unless nullable(@envelope["software"]) { |v| v.is_a?(Hash) }
    end

    # eir-result-v1 is checked against its JSON Schema (04 §11) plus the closed lists.
    def result_shape!
      errors = Schemas.errors(RESULT_PROTOCOL, @envelope)
      raise Ledger::Rejected.new(errors) if errors.any?
      reject("UNSUPPORTED_ACTION", "$.action_type", "not handled by this server yet") unless Ledger::ActionTypes.supported?("TASK_RESULT")
      reject("SCHEMA_INVALID", "$.client_created_at", "expected RFC 3339") unless rfc3339?(@envelope["client_created_at"])
    end

    def nullable(value)
      value.nil? || yield(value)
    end

    def rfc3339?(value)
      value.is_a?(String) && Time.iso8601(value) && true
    rescue ArgumentError
      false
    end

    def no_floats!
      Crypto::CanonicalJson.call(@envelope)
    rescue ArgumentError => e
      reject("FLOAT_PRESENT", "$", e.message)
    end

    def payload_hash!
      return if Crypto::Hashing.json(@envelope["payload"]) == @envelope["payload_hash"]

      reject("PAYLOAD_HASH_MISMATCH", "$.payload_hash", "does not equal sha256 of the canonical payload")
    end

    def resolve_signer!
      key_id = signer_key_id
      if action_type == "REGISTER_KEY"
        public_key = @envelope.dig("payload", "public_key")
        reject("SCHEMA_INVALID", "$.payload.public_key", "required for REGISTER_KEY") unless public_key.is_a?(String) && public_key.present?
        begin
          reject("KEY_ID_MISMATCH", "$.signer_key_id", "does not equal ed25519:sha256(payload.public_key)") unless Crypto::Ed25519.key_id(public_key) == key_id
        rescue ArgumentError
          reject("SCHEMA_INVALID", "$.payload.public_key", "is not valid base64url")
        end
        reject("KEY_ALREADY_REGISTERED", "$.signer_key_id", "this key is already registered") if Contributor.exists?(key_id: key_id)
        @public_key = public_key
        @contributor = nil
      else
        @contributor = Contributor.find_by(key_id: key_id)
        reject("KEY_UNKNOWN", "$.signer_key_id", "no registered contributor has this key") if @contributor.nil?
        reject("KEY_REVOKED", "$.signer_key_id", "revoked at seq #{@contributor.revoked_seq}") if @contributor.revoked?
        @public_key = @contributor.public_key
      end
    end

    def signature!
      return if Crypto::Ed25519.verify(@public_key, @envelope["signature"], Envelope.signed_bytes(@envelope))

      reject("SIGNATURE_INVALID", "$.signature", "does not verify over the canonical envelope with the signer's key")
    end

    def delegation!
      delegation_id = @envelope["delegation_id"]
      if delegation_id
        reject("DELEGATION_INVALID", "$.delegation_id", "only agent keys act under a delegation") unless @contributor&.agent?
        @delegation = AgentDelegation.find_by(id: delegation_id)
        reject("DELEGATION_INVALID", "$.delegation_id", "no such delegation") if @delegation.nil?
        reject("DELEGATION_INVALID", "$.delegation_id", "delegation is for a different key") unless @delegation.delegate_contributor_id == @contributor.id
        reject("DELEGATION_REVOKED", "$.delegation_id", "revoked at seq #{@delegation.revoked_seq}") if @delegation.revoked?
        reject("DELEGATION_EXPIRED", "$.delegation_id", "outside valid_from..valid_until") unless @delegation.in_window?
      elsif @contributor&.agent? && !SELF_SIGNED_ACTIONS.include?(action_type)
        reject("DELEGATION_REQUIRED", "$.delegation_id", "agent keys must act under a principal's delegation")
      end
    end
  end
end
