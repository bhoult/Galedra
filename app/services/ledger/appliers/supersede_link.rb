# frozen_string_literal: true

module Ledger
  module Appliers
    # SUPERSEDE_LINK: a revised assertion about the same evidence and claim
    # (spec 02 §3.6, 04 §2). Superseding another principal's link is a
    # proposal until a different principal accepts it.
    module SupersedeLink
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        old = live!(EvidenceClaimLink, p, "link_id")
        reject("LINK_NOT_ACCEPTED", path("link_id"), "cannot supersede an unaccepted link") unless old.accepted?
        reject("LINK_SUPERSEDED", path("link_id"), "link is already superseded") if old.superseded_by_at(Contribution.maximum(:seq))
        reject("CLAIM_NOT_CURRENT", path("link_id"), "the link's claim is no longer current") unless old.claim.status == "ACTIVE"
        LinkEvidence.link_fields!(p)
        string_or_nil!(p, "reason")
      end

      def self.auto_accept?(validated)
        same_principal?(validated, EvidenceClaimLink.find(validated.payload["link_id"]))
      end

      def self.apply_payload(c, p, index = nil)
        old = EvidenceClaimLink.find(p["link_id"])
        LinkEvidence.create_link(c, p, evidence_item_id: old.evidence_item_id, claim_id: old.claim_id, supersedes_link_id: old.id, index: index)
      end
    end
  end
end
