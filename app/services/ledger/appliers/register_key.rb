# frozen_string_literal: true

module Ledger
  module Appliers
    # REGISTER_KEY (spec 02 §1.2a): self-signed by the key being registered,
    # contributor_id null; creates the contributor row.
    module RegisterKey
      extend Checks

      def self.authorize!(validated)
        payload = validated.payload
        reject("SCHEMA_INVALID", "$.payload.kind", "expected one of #{Contributor::KINDS.join(', ')}") unless Contributor::KINDS.include?(payload["kind"])
        string_or_nil!(payload, "display_name")
        tier = payload.fetch("identity_tier", "PSEUDONYMOUS")
        reject("SCHEMA_INVALID", "$.payload.identity_tier", "expected one of #{Contributor::IDENTITY_TIERS.join(', ')}") unless Contributor::IDENTITY_TIERS.include?(tier)
        reject("SCHEMA_INVALID", "$.payload.metadata", "expected an object") unless payload.fetch("metadata", {}).is_a?(Hash)
      end

      def self.apply(contribution)
        payload = contribution.payload
        Contributor.create!(
          id: Ids.derive(contribution.id, "contributor"),
          key_id: contribution.signer_key_id,
          public_key: payload["public_key"],
          kind: payload["kind"],
          display_name: payload["display_name"],
          identity_tier: payload.fetch("identity_tier", "PSEUDONYMOUS"),
          metadata: payload.fetch("metadata", {}),
          created_seq: contribution.seq
        )
      end
    end
  end
end
