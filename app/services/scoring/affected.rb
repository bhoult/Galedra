# frozen_string_literal: true

module Scoring
  # Which claims a contribution can change the score of (spec 11 §7): only
  # those whose counted links, evidence, groups, acceptance, evaluability, or
  # quarantine state moved at that seq.
  module Affected
    module_function

    # `target` may be passed by a caller that already looked it up (Scoring::
    # Watermark); for the types that name one it is the same row either way.
    def claim_ids(contribution, target: :lookup)
      find = ->(key) { target == :lookup ? Contribution.find_by(id: contribution.payload[key]) : target }
      ids = case contribution.action_type
      when "ACCEPT", "INVALIDATE"
        target = find.call("contribution_id")
        target ? rows_claims(target) : []
      when "QUARANTINE", "RELEASE_QUARANTINE"
        quarantine = contribution.action_type == "QUARANTINE" ? Quarantine.find_by(contribution_id: contribution.id) : Quarantine.find_by(id: contribution.payload["quarantine_id"])
        quarantine ? target_claims(quarantine) : []
      when "TAKEDOWN"
        target = find.call("contribution_id")
        target ? rows_claims(target) : []
      when "AUDIT"
        target = find.call("target_contribution_id")
        target ? rows_claims(target) : []
      else
        contribution.epistemic? ? rows_claims(contribution) : []
      end
      ids.uniq
    end

    def rows_claims(contribution)
      contribution.projection_rows.flat_map { |row| claims_of(row) }
    end

    def claims_of(row)
      case row
      when Claim then [ row.id, row.supersedes_claim_id ].compact
      when EvidenceClaimLink then [ row.claim_id ]
      when EvidenceItem then row.evidence_claim_links.pluck(:claim_id)
      when IndependenceGroupAssignment then row.evidence_item.evidence_claim_links.pluck(:claim_id)
      when IndependenceGroup then EvidenceClaimLink.where(evidence_item_id: row.assignments.select(:evidence_item_id)).pluck(:claim_id)
      when SourceLocation then EvidenceClaimLink.where(evidence_item_id: row.evidence_items.select(:id)).pluck(:claim_id)
      when Source then EvidenceClaimLink.where(evidence_item_id: EvidenceItem.where(source_location_id: row.source_locations.select(:id)).select(:id)).pluck(:claim_id)
      when ClaimMerge then [ row.from_claim_id, row.into_claim_id ]
      when ClaimEvaluabilitySetting then [ row.claim_id ]
      else []
      end
    end

    def target_claims(quarantine)
      if quarantine.target_type == "CLAIM"
        [ quarantine.target_id ]
      else
        source = Source.find_by(id: quarantine.target_id)
        source ? claims_of(source) : []
      end
    end
  end
end
