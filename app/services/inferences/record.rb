# frozen_string_literal: true

module Inferences
  # Records one inference from the connector vocabulary and opens its review
  # task (Stage 25). premises: [{claim, polarity}], conclusion: a claim id.
  module Record
    module_function

    def call(token, conclusion_claim_id:, premises:, inference_type:, rule: nil, strength: "SUPPORTS")
      payload = { "conclusion_claim_id" => conclusion_claim_id.to_s, "premises" => Array(premises).map { |p| { "claim_id" => p["claim"].to_s, "polarity" => p.fetch("polarity", "HOLDS").to_s } },
                  "inference_type" => inference_type.to_s, "rule" => rule.presence, "strength" => strength.presence || "SUPPORTS", "affirms_not_private_individual" => true }.compact
      result = Assistants::Write.call(token, "CREATE_INFERENCE", payload)
      inference = Inference.find(Ledger::Ids.derive(result.contribution.id, "inference"))
      open_review(inference, created_by: token.agent, priority_factor: token.anonymous? ? Investigations::Record::ANONYMOUS_PRIORITY_FACTOR : "1")
      inference
    end

    def open_review(inference, created_by: nil, priority_factor: "1")
      return if Task.where(task_type: "INFERENCE_REVIEW", target_type: "INFERENCE", target_id: inference.id).exists?

      domain = Topics.domain_for_claim(inference.conclusion, Contribution.maximum(:seq)) || Audits::Policy.default_domain
      Tasks::Create.call(task_type: "INFERENCE_REVIEW", target: inference, domain: domain, created_by: created_by, priority_factor: priority_factor)
    end
  end
end
