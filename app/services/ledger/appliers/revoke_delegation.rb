# frozen_string_literal: true

module Ledger
  module Appliers
    # REVOKE_DELEGATION (spec 05 §4): by the principal or the delegate.
    module RevokeDelegation
      extend Checks

      def self.authorize!(validated)
        payload = validated.payload
        delegation = AgentDelegation.find_by(id: payload["delegation_id"].to_s)
        reject("DELEGATION_UNKNOWN", "$.payload.delegation_id", "no such delegation") if delegation.nil?
        reject("ALREADY_REVOKED", "$.payload.delegation_id", "revoked at seq #{delegation.revoked_seq}") if delegation.revoked?
        string_or_nil!(payload, "reason")

        signer_id = validated.contributor&.id
        return if [ delegation.principal_contributor_id, delegation.delegate_contributor_id ].include?(signer_id)

        reject("NOT_AUTHORIZED", "$.signer_key_id", "only the principal or the delegate may revoke a delegation")
      end

      def self.apply(contribution)
        AgentDelegation.find(contribution.payload["delegation_id"]).update!(revoked_seq: contribution.seq)
      end
    end
  end
end
