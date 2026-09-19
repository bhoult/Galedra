# frozen_string_literal: true

module Ledger
  module Appliers
    # CREATE_CLAIM (spec 02 §3.3, 01 §4). A human's own claim is accepted on
    # append; an agent's claim is a proposal until a different principal accepts
    # it (04 §4.3). Atomicity is a warning, never a block (02 §4).
    module CreateClaim
      extend Epistemic

      def self.authorize!(validated)
        claim_fields!(validated.payload)
      end

      def self.claim_fields!(p)
        string!(p, "canonical_text", max: Claim::MAX_TEXT_CHARS)
        unless p["affirms_not_private_individual"] == true
          reject("PRIVATE_INDIVIDUAL_AFFIRMATION_REQUIRED", path("affirms_not_private_individual"),
                 "claims about identifiable private individuals are out of scope; affirm this claim is not one (spec 01 §7)")
        end
        type = enum!(p, "claim_type", Claim::TYPES)
        hash!(p, "qualifiers", default: {})
        live!(Source, p, "source_id") unless p["source_id"].nil?
        live!(Section, p, "section_id") unless p["section_id"].nil? # Stage 20: born placed
        evaluable = p.key?("truth_evaluable") ? boolean!(p, "truth_evaluable") : Claim.default_truth_evaluable(type)
        if evaluable
          reject("SCHEMA_INVALID", path("not_evaluable_reason"), "must be absent when truth_evaluable is true") unless p["not_evaluable_reason"].nil?
        else
          enum!(p, "not_evaluable_reason", Claim::NOT_EVALUABLE_REASONS, default: Claim::DEFAULT_NOT_EVALUABLE[type])
        end
      end

      def self.warnings(validated)
        Claims::Atomicity.warnings(validated.payload["canonical_text"])
      end

      def self.apply_payload(c, p, index = nil)
        create_claim(c, p, index: index)
      end

      def self.create_claim(c, p, supersedes_claim_id: nil, index: nil)
        type = p["claim_type"]
        evaluable = p.key?("truth_evaluable") ? p["truth_evaluable"] : Claim.default_truth_evaluable(type)
        claim = Claim.create!(
          id: row_id(c, "claim", index), contribution_id: c.id, created_seq: c.seq,
          canonical_text: p["canonical_text"], claim_type: type, truth_evaluable: evaluable,
          not_evaluable_reason: evaluable ? nil : (p["not_evaluable_reason"] || Claim::DEFAULT_NOT_EVALUABLE[type]),
          qualifiers: p.fetch("qualifiers", {}), status: "ACTIVE", supersedes_claim_id: supersedes_claim_id,
          extracted_from_source_id: p["source_id"]
        )
        if p["section_id"]
          ClaimPlacement.create!(id: row_id(c, "placement", index), contribution_id: c.id, created_seq: c.seq, claim_id: claim.id,
                                 section_id: p["section_id"], position: ClaimPlacement.where(section_id: p["section_id"]).count)
        end
        claim
      end
    end
  end
end
