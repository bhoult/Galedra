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
        same_result = validated.respond_to?(:in_task) && validated.in_task && validated.respond_to?(:created_ids) && validated.created_ids.include?(group.id)
        reject("TARGET_NOT_ACCEPTED", path("independence_group_id"), "group is not accepted yet") unless group.accepted? || same_result
      end

      def self.apply_payload(c, p, index = nil)
        IndependenceGroupAssignment.create!(
          id: row_id(c, "assignment", index), contribution_id: c.id, created_seq: c.seq,
          evidence_item_id: p["evidence_item_id"], independence_group_id: p["independence_group_id"]
        )
      end
    end
  end
end
