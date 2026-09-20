# frozen_string_literal: true

module Tasks
  # Task-derived review checks for a claim as of a seq (spec 03 §8): an
  # accepted, not invalidated TASK_RESULT for a task targeting the claim.
  module Checks
    CHECK_FOR = { "OPPOSING_EVIDENCE_SEARCH" => "opposing_search_done", "SOURCE_INDEPENDENCE_CHECK" => "independence_reviewed", "QUALIFIER_CHECK" => "qualifiers_reviewed" }.freeze

    module_function

    # Stage 34: self-performed checks are excluded here, before the scorer sees
    # anything. They are recorded and shown, but they never reach task_checks and
    # so can never raise review_coverage — the figure that means someone other
    # than the author has looked. Filtering here rather than flagging inside the
    # scorer keeps the trace shape unchanged, so no new model version is needed
    # for a feature that must not move the number anyway (Invariants 4 and 7).
    def for(claim_id, seq)
      pairs = accepted_results(claim_id, seq).reject { |_, result| self_performed?(result) }
      pairs.map { |task, result| { "check" => CHECK_FOR.fetch(task.task_type), "by" => task.id, "result_contribution_id" => result.id } }
    end

    # What the author checked themselves, for display: {task_type => count}.
    #
    # Keyed on assignments and every task type, not on CHECK_FOR: that map exists
    # to name checklist items, and EVIDENCE_VERIFICATION is not one of them — it
    # contributes evidence links rather than a checklist flag. Counting through
    # it made the most numerous check type invisible to the figure built to
    # report it. Found in a live run, after the display had been called done.
    def self_for(claim_id, seq)
      submitted_assignments(claim_id, seq).select(&:self_performed).group_by { |a| a.task.task_type }.transform_values(&:size)
    end

    # Assignments on this claim's tasks whose result stands at seq.
    def submitted_assignments(claim_id, seq)
      tasks = Task.where(target_type: "CLAIM", target_id: claim_id).pluck(:id)
      return [] if tasks.empty?

      TaskAssignment.where(task_id: tasks).where.not(result_contribution_id: nil).includes(:task).select do |a|
        result = Contribution.find_by(id: a.result_contribution_id)
        result && result.seq <= seq && Contributions::Standing.accepted_at?(result, seq)
      end
    end

    def self_performed?(result)
      TaskAssignment.where(result_contribution_id: result.id, self_performed: true).exists?
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
