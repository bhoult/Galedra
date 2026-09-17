# frozen_string_literal: true

module Ledger
  # One applier per implemented action type. Each responds to
  # authorize!(validated) (raises Ledger::Rejected; run before the row is
  # written) and apply(contribution) (writes projections; run inside
  # Ledger.applying). Epistemic types gain appliers in Stage 3.
  module Appliers
    REGISTRY = {
      "REGISTER_KEY" => "Ledger::Appliers::RegisterKey",
      "DELEGATE" => "Ledger::Appliers::Delegate",
      "REVOKE_KEY" => "Ledger::Appliers::RevokeKey",
      "REVOKE_DELEGATION" => "Ledger::Appliers::RevokeDelegation"
    }.freeze

    def self.for(action_type)
      REGISTRY[action_type]&.constantize
    end

    # Shared helpers for payload checks.
    module Checks
      def reject(code, path, detail)
        raise Ledger::Rejected.new([ { code: code, path: path, detail: detail } ])
      end

      def string_or_nil!(payload, key)
        value = payload[key]
        return if value.nil? || value.is_a?(String)

        reject("SCHEMA_INVALID", "$.payload.#{key}", "expected a string or null")
      end

      def integer_or_nil!(payload, key)
        value = payload[key]
        return if value.nil? || value.is_a?(Integer)

        reject("SCHEMA_INVALID", "$.payload.#{key}", "expected an integer or null")
      end

      def time!(payload, key)
        Time.iso8601(payload[key].to_s)
      rescue ArgumentError
        reject("SCHEMA_INVALID", "$.payload.#{key}", "expected RFC 3339")
      end
    end
  end
end
