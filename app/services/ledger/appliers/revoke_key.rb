# frozen_string_literal: true

module Ledger
  module Appliers
    # REVOKE_KEY (spec 05 §4): by the key itself or by a human principal that
    # holds an active delegation to it. Takes effect at its seq. A declared
    # compromised_since marks that key's later contributions CHALLENGED; Stage 7
    # queues them for audit.
    module RevokeKey
      extend Checks

      def self.authorize!(validated)
        payload = validated.payload
        target = Contributor.find_by(key_id: payload["key_id"].to_s)
        reject("KEY_UNKNOWN", "$.payload.key_id", "no registered contributor has this key") if target.nil?
        reject("ALREADY_REVOKED", "$.payload.key_id", "revoked at seq #{target.revoked_seq}") if target.revoked?
        reject("NOT_AUTHORIZED", "$.payload.key_id", "the system key cannot be revoked") if target.system?
        integer_or_nil!(payload, "compromised_since")
        string_or_nil!(payload, "reason")

        signer = validated.contributor
        return if Governance::Moderators.moderator?(signer) # suspension (spec 05 §13)

        self_revocation = signer && signer.id == target.id
        principal = signer&.human? && AgentDelegation.where(principal_contributor_id: signer.id, delegate_contributor_id: target.id, revoked_seq: nil).exists?
        return if self_revocation || principal

        reject("NOT_AUTHORIZED", "$.signer_key_id", "only the key itself or its delegating principal may revoke it")
      end

      def self.apply(contribution)
        payload = contribution.payload
        target = Contributor.find_by!(key_id: payload["key_id"])
        target.update!(revoked_seq: contribution.seq)

        compromised_since = payload["compromised_since"]
        return if compromised_since.nil?

        Contribution.where(signer_key_id: target.key_id)
                    .where("seq >= ? AND seq < ?", compromised_since, contribution.seq)
                    .update_all(current_status: Contribution::CHALLENGED)
      end
    end
  end
end
