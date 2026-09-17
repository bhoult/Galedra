# frozen_string_literal: true

module Governance
  # Read-side rules for quarantined content (spec 05 §13): what is withheld,
  # and the public stub that stays at the same URL.
  module Quarantines
    APPEAL_PATH = "/api/v1/moderation"

    def self.live_for(target_type, target_id)
      Quarantine.live.where(target_type: target_type, target_id: target_id).order(created_seq: :desc).first
    end

    def self.quarantined_at?(target_type, target_id, seq)
      Quarantine.active_at(seq).where(target_type: target_type, target_id: target_id).exists?
    end

    def self.quarantined_claim_ids
      Quarantine.live.where(target_type: "CLAIM").select(:target_id)
    end

    def self.quarantined_source_ids
      Quarantine.live.where(target_type: "SOURCE").select(:target_id)
    end

    # The source that an evidence item's text depends on.
    def self.evidence_withheld?(item)
      Quarantine.live.where(target_type: "SOURCE", target_id: item.source_location.source_id).exists?
    end

    # Contributions whose payloads carry quarantined text and are therefore
    # withheld from the public log endpoints while the quarantine is live.
    def self.withheld_contribution_ids
      claim_ids = Claim.where(id: quarantined_claim_ids).pluck(:contribution_id)
      source_ids = quarantined_source_ids
      sources = Source.where(id: source_ids).pluck(:contribution_id)
      locations = SourceLocation.where(source_id: source_ids)
      location_contributions = locations.pluck(:contribution_id)
      evidence = EvidenceItem.where(source_location_id: locations.select(:id)).pluck(:contribution_id)
      (claim_ids + sources + location_contributions + evidence).uniq
    end

    def self.stub(quarantine)
      contribution = quarantine.contribution
      {
        quarantined: true,
        quarantine: {
          id: quarantine.id, seq: quarantine.created_seq, at: contribution.received_at_rfc3339,
          moderator_key_id: contribution.signer_key_id, reason: quarantine.reason,
          appeal_status: quarantine.released? ? "RELEASED" : "OPEN", appeal_path: APPEAL_PATH
        }
      }
    end
  end
end
