# frozen_string_literal: true

module Ledger
  module Appliers
    # INVALIDATE (spec 02 §5): a correction that closes the target's projection
    # windows at this seq. By the system key (audit outcomes, Stage 7) or by
    # the target's own principal withdrawing its work (or its agent's work).
    module Invalidate
      extend Checks

      def self.authorize!(validated)
        payload = validated.payload
        id = uuid!(payload, "contribution_id")
        target = Contribution.find_by(id: id)
        reject("TARGET_UNKNOWN", path("contribution_id"), "no such contribution") if target.nil?
        reject("NOT_INVALIDATABLE", path("contribution_id"), "only epistemic contributions are invalidated") unless target.epistemic?
        reject("ALREADY_INVALIDATED", path("contribution_id"), "already invalidated") if target.current_status == Contribution::INVALIDATED
        string!(payload, "reason")

        signer = validated.contributor
        return if signer&.system?

        principal = signer&.human? ? signer : validated.delegation&.principal
        return if principal && principal.id == target.principal_contributor_id

        reject("NOT_AUTHORIZED", "$.signer_key_id", "only the contribution's principal or the system may invalidate it")
      end

      def self.apply(contribution)
        target = Contribution.find(contribution.payload["contribution_id"])
        target.update!(current_status: Contribution::INVALIDATED)
        Appliers.for(target.action_type)&.invalidate(target, contribution.seq)
      end
    end
  end
end
