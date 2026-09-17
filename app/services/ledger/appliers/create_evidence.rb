# frozen_string_literal: true

module Ledger
  module Appliers
    # CREATE_EVIDENCE (spec 02 §3.3).
    module CreateEvidence
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        live!(SourceLocation, p, "source_location_id")
        enum!(p, "observation_type", EvidenceItem::OBSERVATION_TYPES)
        string!(p, "statement", max: 2_000)
        hash_or_nil!(p, "structured_value")
        assessment = hash!(p, "assessment", default: {})
        enum!(assessment, "authenticity", EvidenceItem::AUTHENTICITY, default: "UNVERIFIED")
        enum!(assessment, "extraction", EvidenceItem::EXTRACTION, default: "UNVERIFIED")
      end

      def self.apply(c)
        p = c.payload
        EvidenceItem.create!(
          id: Ids.derive(c.id, "evidence"), contribution_id: c.id, created_seq: c.seq,
          source_location_id: p["source_location_id"], observation_type: p["observation_type"],
          statement: p["statement"], structured_value: p["structured_value"],
          assessment: EvidenceItem::DEFAULT_ASSESSMENT.merge(p.fetch("assessment", {}))
        )
      end
    end
  end
end
