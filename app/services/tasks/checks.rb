# frozen_string_literal: true

module Tasks
  # Task-derived review checks for a claim as of a seq (spec 03 §8): an
  # accepted, not invalidated TASK_RESULT for a task targeting the claim.
  module Checks
    CHECK_FOR = { "OPPOSING_EVIDENCE_SEARCH" => "opposing_search_done", "SOURCE_INDEPENDENCE_CHECK" => "independence_reviewed", "QUALIFIER_CHECK" => "qualifiers_reviewed" }.freeze

    module_function

    def for(claim_id, seq)
      accepted_results(claim_id, seq).map { |task, result| { "check" => CHECK_FOR.fetch(task.task_type), "by" => task.id, "result_contribution_id" => result.id } }
    end

    def opposing_search_done?(contribution_id, seq)
      contribution = Contribution.find_by(id: contribution_id)
      return false if contribution.nil?

      Scoring::Affected.rows_claims(contribution).uniq.any? { |claim_id| accepted_results(claim_id, seq).any? { |task, _| task.task_type == "OPPOSING_EVIDENCE_SEARCH" } }
    end

    # [task, result_contribution] pairs accepted at seq and not invalidated by seq.
    def accepted_results(claim_id, seq)
      tasks = Task.where(target_type: "CLAIM", target_id: claim_id, task_type: CHECK_FOR.keys)
      tasks.flat_map do |task|
        Contribution.where(action_type: "TASK_RESULT", task_id: task.id).where("seq <= ?", seq).filter_map do |result|
          Contributions::Standing.accepted_at?(result, seq) ? [ task, result ] : nil
        end
      end
    end
  end
end
