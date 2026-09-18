# frozen_string_literal: true

module Ledger
  module Appliers
    # CREATE_CLAIM_EDGE (spec 02 §3.3).
    module CreateClaimEdge
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        created = Appliers.same_result_ids(validated)
        from = current_claim!(p, "from_claim_id", created_ids: created)
        to = current_claim!(p, "to_claim_id", created_ids: created)
        reject("SCHEMA_INVALID", path("to_claim_id"), "must differ from from_claim_id") if from.id == to.id
        enum!(p, "relationship_type", ClaimEdge::TYPES)
      end

      def self.apply_payload(c, p, index = nil)
        ClaimEdge.create!(
          id: row_id(c, "edge", index), contribution_id: c.id, created_seq: c.seq,
          from_claim_id: p["from_claim_id"], to_claim_id: p["to_claim_id"], relationship_type: p["relationship_type"]
        )
      end
    end
  end
end
