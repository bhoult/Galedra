# frozen_string_literal: true

module Ledger
  module Appliers
    # PLACE_CLAIM (Stage 20): files an existing claim in a section. Filing is
    # organisation, not certification: accepted on validation for any
    # principal, reversible by INVALIDATE. The same claim in the same section
    # twice is a duplicate.
    module PlaceClaim
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        claim = current_claim!(p, "claim_id")
        section = live!(Section, p, "section_id")
        integer_or_nil!(p, "position")
        reject("DUPLICATE", path("section_id"), "the claim is already placed in this section") if ClaimPlacement.live.exists?(claim_id: claim.id, section_id: section.id)
      end

      def self.auto_accept?(_validated) = true

      def self.apply_payload(c, p, index = nil)
        section = Section.find(p["section_id"])
        ClaimPlacement.create!(
          id: row_id(c, "placement", index), contribution_id: c.id, created_seq: c.seq,
          claim_id: p["claim_id"], section_id: section.id, position: p["position"] || ClaimPlacement.where(section_id: section.id).count
        )
      end
    end
  end
end
