# frozen_string_literal: true

module Ledger
  module Appliers
    # LINK_EVIDENCE (spec 02 §3.3). The claim must be accepted and current.
    module LinkEvidence
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        live!(EvidenceItem, p, "evidence_item_id")
        current_claim!(p, "claim_id")
        link_fields!(p)
      end

      def self.link_fields!(p)
        enum!(p, "direction", EvidenceClaimLink::DIRECTIONS)
        enum!(p, "relevance_strength", EvidenceClaimLink::STRENGTHS)
        integer!(p, "interpretive_steps", range: 0..EvidenceClaimLink::MAX_STEPS)
        string_or_nil!(p, "note")
      end

      def self.apply_payload(c, p, index = nil)
        create_link(c, p, evidence_item_id: p["evidence_item_id"], claim_id: p["claim_id"], index: index)
      end

      def self.create_link(c, p, evidence_item_id:, claim_id:, supersedes_link_id: nil, index: nil)
        EvidenceClaimLink.create!(
          id: row_id(c, "link", index), contribution_id: c.id, created_seq: c.seq,
          evidence_item_id: evidence_item_id, claim_id: claim_id, direction: p["direction"],
          relevance_strength: p["relevance_strength"], interpretive_steps: p["interpretive_steps"],
          note: p["note"], supersedes_link_id: supersedes_link_id
        )
      end
    end
  end
end
