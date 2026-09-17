# frozen_string_literal: true

module Ledger
  module Appliers
    # ASSIGN_INDEPENDENCE_GROUP (spec 02 §3.3): its own contribution so it can
    # be audited separately; the latest counted assignment governs.
    module AssignIndependenceGroup
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        live!(EvidenceItem, p, "evidence_item_id")
        group = live!(IndependenceGroup, p, "independence_group_id")
        reject("TARGET_NOT_ACCEPTED", path("independence_group_id"), "group is not accepted yet") unless group.accepted?
      end

      def self.apply(c)
        p = c.payload
        IndependenceGroupAssignment.create!(
          id: Ids.derive(c.id, "assignment"), contribution_id: c.id, created_seq: c.seq,
          evidence_item_id: p["evidence_item_id"], independence_group_id: p["independence_group_id"]
        )
      end
    end
  end
end
