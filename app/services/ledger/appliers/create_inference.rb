# frozen_string_literal: true

module Ledger
  module Appliers
    # CREATE_INFERENCE (Stage 25): conclusion_claim_id; premises, two to twelve
    # {claim_id, polarity}; inference_type; rule (untrusted display text, at
    # most 500 characters); strength; affirms_not_private_individual. Also
    # records one DERIVED_FROM edge from the conclusion to each premise, so
    # downstream counts and the edge display need not know about inferences.
    # Cycles across inferences are recorded, never followed by any scorer.
    module CreateInference
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        created = Appliers.same_result_ids(validated)
        conclusion = current_claim!(p, "conclusion_claim_id", created_ids: created)
        premises = p["premises"]
        reject("SCHEMA_INVALID", path("premises"), "expected #{Inference::MIN_PREMISES} to #{Inference::MAX_PREMISES} premises of {claim_id, polarity}") unless premises.is_a?(Array) && premises.size.between?(Inference::MIN_PREMISES, Inference::MAX_PREMISES)
        seen = []
        premises.each_with_index do |pr, i|
          at = "#{path('premises')}[#{i}]"
          reject("SCHEMA_INVALID", at, "expected {claim_id, polarity}") unless pr.is_a?(Hash)
          claim = current_claim!(pr, "claim_id", created_ids: created)
          reject("SCHEMA_INVALID", "#{at}.claim_id", "the conclusion cannot be one of its own premises") if claim.id == conclusion.id
          reject("SCHEMA_INVALID", "#{at}.claim_id", "the same claim appears twice") if seen.include?(claim.id)
          seen << claim.id
          reject("SCHEMA_INVALID", "#{at}.polarity", "expected HOLDS or FAILS") unless InferencePremise::POLARITIES.include?(pr["polarity"])
        end
        enum!(p, "inference_type", Inference::TYPES)
        enum!(p, "strength", Inference::STRENGTHS, default: "SUPPORTS")
        rule = string_or_nil!(p, "rule")
        reject("SCHEMA_INVALID", path("rule"), "at most #{Inference::MAX_RULE} characters") if rule && rule.length > Inference::MAX_RULE
        reject("PRIVATE_INDIVIDUAL_AFFIRMATION_REQUIRED", path("affirms_not_private_individual"), "affirm this step concerns no identifiable private individual") unless p["affirms_not_private_individual"] == true
      end

      def self.apply_payload(c, p, index = nil)
        inference = Inference.create!(
          id: row_id(c, "inference", index), contribution_id: c.id, created_seq: c.seq, conclusion_claim_id: p["conclusion_claim_id"],
          inference_type: p["inference_type"], rule: p["rule"], strength: p.fetch("strength", "SUPPORTS")
        )
        p["premises"].each_with_index do |pr, i|
          sub = index ? "#{index}-#{i}" : i
          InferencePremise.create!(id: row_id(c, "premise", sub), contribution_id: c.id, created_seq: c.seq, inference_id: inference.id,
                                   claim_id: pr["claim_id"], polarity: pr["polarity"], position: i)
          ClaimEdge.create!(id: row_id(c, "edge", sub), contribution_id: c.id, created_seq: c.seq,
                            from_claim_id: p["conclusion_claim_id"], to_claim_id: pr["claim_id"], relationship_type: "DERIVED_FROM")
        end
        inference
      end
    end
  end
end
