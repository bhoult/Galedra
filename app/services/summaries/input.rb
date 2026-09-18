# frozen_string_literal: true

module Summaries
  # The deterministic input to a summary (spec 04 §10): claim, state, checklist,
  # kept links with evidence statements (never notes), suppressed count,
  # related claims, task checks, audits on counted links, model and snapshot.
  # Its hash is the cache key; the cite set is everything a sentence may cite.
  module Input
    module_function

    def build(claim, seq, model, result = Scoring::Score.call(claim, seq, model))
      links = result.trace["links"]
      statements = EvidenceItem.where(id: links.map { |l| l["evidence"] }).pluck(:id, :statement).to_h
      kept = links.select { |l| l["effective_weight"] && BigDecimal(l["effective_weight"]).positive? }
      qualifiers = links.select { |l| l["reason"] == "non_directional" && l["direction"] == "QUALIFY" }
      suppressed = links.select { |l| l["reason"] == "dependent_strongest_only" }
      related = (claim.incoming_edges.counted_at(seq).includes(:from_claim).map { |e| [ e.from_claim, e.relationship_type, "incoming" ] } +
                 claim.outgoing_edges.counted_at(seq).includes(:to_claim).map { |e| [ e.to_claim, e.relationship_type, "outgoing" ] })
      related_entries = related.reject { |other, _, _| Governance::Quarantines.live_for("CLAIM", other.id) }.map do |other, type, dir|
        { "claim_id" => other.id, "relation" => type, "direction" => dir, "assessment_state" => Scoring::Score.call(other, seq, model).assessment_state }
      end
      # Audits on every link the claim has had up to the seq, so a rejected
      # verification stays citable after its link is invalidated (08 §9).
      link_contributions = claim.evidence_claim_links.where(arel_link_created_lteq(seq)).pluck(:contribution_id)
      audits = Audit.where(target_contribution_id: link_contributions).where("created_seq <= ?", seq).order(:created_seq)
      {
        "claim" => { "id" => claim.id, "text" => claim.canonical_text, "type" => claim.claim_type },
        "model" => model.full_name, "snapshot_seq" => seq,
        "assessment_state" => result.assessment_state, "probability" => result.probability,
        "not_applicable_reason" => result.not_applicable_reason, "model_dependent" => result.model_dependent,
        "review_checklist" => result.review_checklist, "review_coverage" => result.review_coverage,
        "kept" => kept.map { |l| { "link" => l["link"], "evidence" => l["evidence"], "group" => l["group"], "direction" => l["direction"], "statement" => statements[l["evidence"]] } },
        "qualifiers" => qualifiers.map { |l| { "link" => l["link"], "evidence" => l["evidence"], "statement" => statements[l["evidence"]] } },
        "suppressed" => suppressed.map { |l| { "link" => l["link"], "evidence" => l["evidence"], "group" => l["group"], "kept" => l["kept"] } },
        "related" => related_entries,
        "audits" => audits.map { |a| { "audit" => a.id, "result" => a.result, "overturned" => a.invalidated? } },
        "task_results" => Tasks::Checks.accepted_results(claim.id, seq).map { |task, result| { "task_id" => task.id, "task_type" => task.task_type, "outcome" => result.payload&.dig("outcome") } }
      }
    end

    def arel_link_created_lteq(seq) = EvidenceClaimLink.arel_table[:created_seq].lteq(seq)

    def hash(input) = Crypto::Hashing.json(input)

    # Everything a sentence may cite.
    def cite_set(input)
      cites = [ "coverage:#{input.dig('claim', 'id')}" ]
      cites += input["kept"].flat_map { |k| [ k["evidence"], k["group"] ] }
      cites += input["qualifiers"].map { |q| q["evidence"] }
      cites += input["suppressed"].flat_map { |s| [ s["evidence"], s["group"] ] }
      cites += input["related"].map { |r| r["claim_id"] }
      cites += input["review_checklist"].values.flat_map { |v| v["by"] }
      cites += input["audits"].map { |a| "audit:#{a['audit']}" }
      cites.compact.uniq
    end
  end
end
