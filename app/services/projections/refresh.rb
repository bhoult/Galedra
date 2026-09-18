# frozen_string_literal: true

module Projections
  # Recomputes the cached "current view" columns on claims and evidence items
  # from their windowed rows after an ACCEPT or INVALIDATE. Deterministic given
  # the log, so replay reproduces the columns.
  module Refresh
    def self.after(contribution)
      contribution.projection_rows.each do |row|
        case row
        when Claim
          claim(row)
          claim(row.supersedes_claim)
        when ClaimMerge
          claim(row.from_claim)
          claim(row.into_claim)
        when ClaimEvaluabilitySetting then claim(row.claim)
        when IndependenceGroupAssignment then evidence(row.evidence_item)
        end
      end
    end

    def self.claim(claim)
      return if claim.nil?

      merge = claim.merges_from.live.accepted.order(accepted_seq: :desc).first
      superseder = Claim.live.accepted.where(supersedes_claim_id: claim.id).order(accepted_seq: :desc).first
      status = if Governance::Quarantines.live_for("CLAIM", claim.id) then "QUARANTINED"
      elsif merge then "MERGED"
      elsif superseder then "SUPERSEDED"
      elsif claim.invalidated? then "RETIRED"
      else "ACTIVE"
      end
      setting = claim.evaluability_settings.live.accepted.order(accepted_seq: :desc).first
      evaluable, reason = setting ? [ setting.truth_evaluable, setting.not_evaluable_reason ] : [ claim.original_truth_evaluable, claim.original_not_evaluable_reason ]
      claim.update!(status: status, merged_into_id: merge&.into_claim_id, superseded_by_id: superseder&.id,
                    truth_evaluable: evaluable, not_evaluable_reason: reason)
    end

    def self.evidence(item)
      return if item.nil?

      assignment = item.assignments.live.accepted.order(accepted_seq: :desc).first
      item.update!(independence_group_id: assignment&.independence_group_id)
    end
  end
end
