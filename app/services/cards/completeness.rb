# frozen_string_literal: true

module Cards
  # How complete the review of a claim is, shown beside its score, and of an
  # investigation or outline as a whole (owner request, 2026-09-29).
  #
  # Built from the review checklist the score already carries (spec 03 §8), one
  # segment per item, and two kinds of done kept apart as Stage 34 keeps them:
  #
  # - COUNTED: the item is satisfied in the score, so it is in review_coverage.
  # - OWN: only the claim's own author has done that check. It is recorded and
  #   shown, and never counted, because a check by the author is not somebody
  #   else looking.
  #
  # "Counted" rather than "by someone else": the primary-source item is met by a
  # primary source among the counted evidence, and independence by grouping, so
  # neither is a statement about who looked. Nothing here is a score input or a
  # new figure about truth; it restates the checklist and the task record.
  module Completeness
    LABELS = {
      "primary_source_reviewed" => "primary source read",
      "opposing_search_done" => "opposing evidence searched for",
      "independence_reviewed" => "sources checked for a shared origin",
      "qualifiers_reviewed" => "qualifiers checked"
    }.freeze
    STATES = {
      counted: "done, and counted in review coverage",
      own: "done only by the claim's own author, so not counted",
      none: "not done yet"
    }.freeze

    module_function

    # {claim_id => score result} in, {claim_id => meter} out.
    def for_results(results, seq)
      own = own_checks(results.keys, seq)
      results.to_h { |id, result| [ id, meter(result, own.fetch(id, Set.new)) ] }
    end

    def meter(result, own_types = Set.new)
      checklist = result.respond_to?(:review_checklist) && result.review_checklist.is_a?(Hash) ? result.review_checklist : {}
      segments = checklist.map do |item, value|
        task_type = Scoring::Checklist::TASK_CHECKS[item]
        state = if value["ok"] then :counted
        elsif task_type && own_types.include?(task_type) then :own
        else :none
        end
        { item: item, label: LABELS.fetch(item, item.tr("_", " ")), state: state }
      end
      { segments: segments, total: segments.size,
        counted: segments.count { |s| s[:state] == :counted }, own: segments.count { |s| s[:state] == :own } }
    end

    # Every claim's segments summed: the whole of an investigation or outline.
    def total(meters)
      segments = meters.flat_map { |m| m[:segments] }
      n = segments.size
      counted = segments.count { |s| s[:state] == :counted }
      own = segments.count { |s| s[:state] == :own }
      { claims: meters.size, total: n, counted: counted, own: own,
        done_percent: n.zero? ? 0 : ((counted + own) * 100 / n), counted_percent: n.zero? ? 0 : (counted * 100 / n) }
    end

    # {claim_id => Set of task types} the claim's own author has answered with a
    # result standing at seq. Four statements however many claims: this runs
    # under an outline of hundreds (the per-row defect CLAUDE.md warns about).
    def own_checks(claim_ids, seq)
      return {} if claim_ids.empty?

      tasks = Task.where(target_type: "CLAIM", target_id: claim_ids, task_type: Scoring::Checklist::TASK_CHECKS.values)
                  .pluck(:id, :target_id, :task_type).to_h { |id, claim_id, type| [ id, [ claim_id, type ] ] }
      return {} if tasks.empty?

      results = Contribution.where(action_type: "TASK_RESULT", task_id: tasks.keys).where("seq <= ?", seq).select(:id, :task_id, :seq).to_a
      standing = Contributions::Standing.accepted_set(results, seq)
      own = TaskAssignment.where(result_contribution_id: standing.to_a, self_performed: true).pluck(:result_contribution_id).to_set
      results.each_with_object({}) do |r, out|
        next unless own.include?(r.id)

        claim_id, type = tasks[r.task_id]
        (out[claim_id] ||= Set.new) << type
      end
    end
  end
end
