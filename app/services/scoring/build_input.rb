# frozen_string_literal: true

module Scoring
  # Builds the scorer input (spec 11 §12) for a claim as of a snapshot seq:
  # counted links (03 §4 Step 1: accepted, active, not superseded, with an
  # active evidence item and location, and no live quarantine on the source),
  # evidence facts as of that seq, audit state, and task-derived checks.
  module BuildInput
    module_function

    def call(claim, seq)
      evaluable, reason = claim.evaluability_at(seq)
      {
        "claim" => { "id" => claim.id, "type" => claim.claim_type, "truth_evaluable" => evaluable, "not_evaluable_reason" => reason },
        "snapshot_seq" => seq,
        "links" => links_for(claim, seq),
        "task_checks" => Tasks::Checks.for(claim.id, seq)
      }
    end

    def links_for(claim, seq)
      links = claim.evidence_claim_links.effective_at(seq).includes(evidence_item: { source_location: :source }).order(:id)
      links.filter_map do |link|
        item = link.evidence_item
        location = item.source_location
        next unless item.active_at?(seq) && location.active_at?(seq) && location.source.active_at?(seq)
        next if Governance::Quarantines.quarantined_at?("SOURCE", location.source_id, seq)
        next if Audits::Status.challenged?(link.contribution, seq)

        {
          "id" => link.id, "evidence_id" => item.id, "direction" => link.direction,
          "relevance_strength" => link.relevance_strength, "interpretive_steps" => link.interpretive_steps,
          "created_seq" => link.created_seq,
          "audit_confirmed" => Audits::Status.confirmed?(link.contribution_id, seq),
          "evidence" => {
            "observation_type" => item.observation_type,
            "independence_group_id" => item.independence_group_at(seq)&.id,
            "source_type" => location.source.source_type,
            "assessment" => item.assessment,
            "created_seq" => item.created_seq
          }
        }
      end
    end
  end
end
