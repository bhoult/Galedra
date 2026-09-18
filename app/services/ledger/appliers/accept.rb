# frozen_string_literal: true

module Ledger
  module Appliers
    # ACCEPT (spec 02 §1.1a): by the system key after validation, or by a
    # different principal (a human, or an agent whose delegation lists ACCEPT
    # under permissions.allowed_actions). Never by the same principal.
    module Accept
      extend Checks

      def self.authorize!(validated)
        target = target_for(validated.payload)
        signer = validated.contributor
        return if signer&.system?

        reject("NOT_AUTHORIZED", path("basis"), "only the system restores after a re-audit") if validated.payload["basis"] == RESTORE_BASIS
        reject("NOT_AUTHORIZED", "$.signer_key_id", "only a human or a delegated agent may accept") unless signer&.human? || agent_may_accept?(validated)
        signer_principal = signer.human? ? signer : validated.delegation&.principal
        if signer_principal.nil? || signer_principal.id == target.principal_contributor_id
          reject("NOT_AUTHORIZED", "$.payload.contribution_id", "a contribution cannot be accepted by its own principal")
        end
      end

      def self.agent_may_accept?(validated)
        validated.contributor&.agent? && Array(validated.delegation&.permissions&.dig("allowed_actions")).include?("ACCEPT")
      end

      RESTORE_BASIS = "RESTORED_AFTER_RE_AUDIT"

      def self.target_for(payload)
        id = uuid!(payload, "contribution_id")
        target = Contribution.find_by(id: id)
        reject("TARGET_UNKNOWN", path("contribution_id"), "no such contribution") if target.nil?
        reject("NOT_ACCEPTABLE", path("contribution_id"), "only epistemic contributions are accepted") unless target.epistemic?
        reject("ALREADY_ACCEPTED", path("contribution_id"), "already accepted") if target.current_status == Contribution::ACCEPTED
        return target if payload["basis"] == RESTORE_BASIS && target.current_status == Contribution::INVALIDATED

        reject("NOT_ACCEPTABLE", path("contribution_id"), "contribution is #{target.current_status.downcase}") unless target.current_status == Contribution::PENDING
        target
      end

      def self.apply(contribution)
        target = Contribution.find(contribution.payload["contribution_id"])
        restoring = target.current_status == Contribution::INVALIDATED
        target.update!(current_status: Contribution::ACCEPTED)
        if restoring
          Restore.copy_rows(target, contribution)
          Projections::Refresh.after(target)
        else
          Appliers.for(target.action_type)&.accept(target, contribution.seq)
        end
      end
    end
  end
end
