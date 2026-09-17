# frozen_string_literal: true

module Ledger
  module Appliers
    # QUARANTINE (spec 05 §13): a moderator restricts a claim or source for a
    # reason from the closed list. Disagreement with a claim is never a reason.
    module Quarantine
      extend Checks

      def self.authorize!(validated)
        reject("NOT_AUTHORIZED", "$.signer_key_id", "only a moderator key may quarantine") unless Governance::Moderators.moderator?(validated.contributor)
        p = validated.payload
        type = enum!(p, "target_type", ::Quarantine::TARGET_TYPES)
        model = type == "CLAIM" ? Claim : Source
        target = live!(model, p, "target_id")
        enum!(p, "reason", ::Quarantine::REASONS)
        string_or_nil!(p, "note")
        reject("ALREADY_QUARANTINED", path("target_id"), "target is already quarantined") if Governance::Quarantines.live_for(type, target.id)
      end

      def self.apply(c)
        p = c.payload
        ::Quarantine.create!(
          id: Ids.derive(c.id, "quarantine"), contribution_id: c.id, created_seq: c.seq,
          target_type: p["target_type"], target_id: p["target_id"], reason: p["reason"], note: p["note"]
        )
        Projections::Refresh.claim(Claim.find(p["target_id"])) if p["target_type"] == "CLAIM"
      end
    end
  end
end
