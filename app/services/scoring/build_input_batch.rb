# frozen_string_literal: true

module Scoring
  # `BuildInput.call` for many (claim, seq) pairs at once, returning exactly
  # what calling it once per pair returns (Invariant 4).
  #
  # Every caller that scores a set already had the set in hand and then asked
  # per claim: the evidence links, each item's independence group, the claim's
  # placements and their sources, its evaluability settings and the creating
  # contribution behind them, its check tasks, their results, their standing and
  # whether each was self-performed. Measured on the development node, 60 claims
  # of the weaknesses page issued 929 statements, 179 of them one independence
  # lookup per evidence item (2026-09-23; CLAUDE.md names this defect).
  #
  # Since Stage 38 each claim is scored at its own watermark, so a pair's seq
  # differs from its neighbour's. Each table is therefore loaded once up to the
  # highest seq in the set, and every window is applied per pair in Ruby with
  # the same predicate the SQL scope uses (`counted_at?`, `active_at?`). Where
  # the query it replaces picks one row by an ordering SQL may break
  # arbitrarily — `order(accepted_seq: :desc).first` with two rows accepted at
  # one seq — this does not guess: it asks the database the original question
  # for that pair, so a tie resolves exactly as it always did.
  class BuildInputBatch
    def self.call(pairs) = new(pairs).inputs

    # pairs: [[claim, seq], ...]
    def initialize(pairs)
      @pairs = pairs
      @claims = pairs.map(&:first).uniq(&:id)
      @max = pairs.map(&:last).max
      load!
    end

    def inputs
      @pairs.to_h do |claim, seq|
        evaluable, reason = evaluability(claim, seq)
        [ claim.id, {
          "claim" => { "id" => claim.id, "type" => claim.claim_type, "truth_evaluable" => evaluable, "not_evaluable_reason" => reason },
          "snapshot_seq" => seq,
          "links" => links(claim, seq),
          "task_checks" => task_checks(claim.id, seq)
        } ]
      end
    end

    private

    def load!
      ids = @claims.map(&:id)
      within = ->(scope) { scope.where(scope.arel_table[:created_seq].lteq(@max)) }

      # Evaluability: the settings, and the creating contribution's payload only
      # — the whole row is ~1.9 KB, and this reads two keys of it.
      @settings = within.call(ClaimEvaluabilitySetting.where(claim_id: ids)).to_a.group_by(&:claim_id)
      @payloads = Contribution.where(id: @claims.map(&:contribution_id)).pluck(:id, :payload).to_h

      # Links, with what the per-claim query included.
      @links = within.call(EvidenceClaimLink.where(claim_id: ids))
                     .includes(:contribution, evidence_item: { source_location: :source }).to_a.group_by(&:claim_id)
      # `not_superseded_at` asks the whole table, not the claim's own links, so
      # this does too: every link that supersedes one of these, wherever it is.
      link_ids = @links.values.flatten.map(&:id)
      @superseders = within.call(EvidenceClaimLink.where(supersedes_link_id: link_ids)).to_a.group_by(&:supersedes_link_id)
      items = @links.values.flatten.filter_map(&:evidence_item_id).uniq
      @assignments = within.call(IndependenceGroupAssignment.where(evidence_item_id: items)).to_a.group_by(&:evidence_item_id)
      group_ids = @assignments.values.flatten.map(&:independence_group_id).uniq
      @groups = IndependenceGroup.where(id: group_ids).pluck(:id).to_set

      # Placements and the sources of their sections, for own_origins.
      @placements = within.call(ClaimPlacement.where(claim_id: ids)).to_a.group_by(&:claim_id)
      section_ids = @placements.values.flatten.filter_map(&:section_id).uniq
      @section_source = Section.where(id: section_ids).pluck(:id, :source_id).to_h
      @sources = Source.where(id: @section_source.values.uniq).index_by(&:id)

      # Check tasks, their results up to the highest seq, and every standing
      # entry naming those results.
      @tasks = Task.where(target_type: "CLAIM", target_id: ids, task_type: Tasks::Checks::CHECK_FOR.keys).order(:id).to_a.group_by(&:target_id)
      task_ids = @tasks.values.flatten.map(&:id)
      @results = task_ids.empty? ? {} : Contribution.where(action_type: "TASK_RESULT", task_id: task_ids).where("seq <= ?", @max)
                                                    .order(:seq).pluck(:id, :task_id, :seq).group_by { |_, task_id, _| task_id }
      result_ids = @results.values.flatten(1).map(&:first)
      @standing = standing_timeline(result_ids)
      @self_performed = result_ids.empty? ? Set.new : TaskAssignment.where(result_contribution_id: result_ids, self_performed: true).pluck(:result_contribution_id).to_set
    end

    # What `claim.evaluability_at(seq)` returns.
    def evaluability(claim, seq)
      counted = (@settings[claim.id] || []).select { |s| s.counted_at?(seq) }
      if counted.empty?
        return [ claim.original_truth_evaluable, claim.original_not_evaluable_reason ] unless @payloads.key?(claim.contribution_id)

        payload = @payloads[claim.contribution_id]
        return [ claim.original_truth_evaluable(payload), claim.original_not_evaluable_reason(payload) ]
      end

      top = counted.map(&:accepted_seq).max
      return claim.evaluability_at(seq) if counted.count { |s| s.accepted_seq == top } > 1

      setting = counted.find { |s| s.accepted_seq == top }
      [ setting.truth_evaluable, setting.not_evaluable_reason ]
    end

    # What `BuildInput.links_for` returns, given the links `effective_at(seq)`
    # would select, in `order(:id)`.
    def links(claim, seq)
      all = @links[claim.id] || []
      effective = all.select { |l| l.counted_at?(seq) && (@superseders[l.id] || []).none? { |s| s.counted_at?(seq) } }.sort_by(&:id)
      origins = own_origins(claim.id, seq)
      editions = BuildInput.other_editions(claim, seq)
      BuildInput.link_entries(effective, seq, origins, editions) { |item| independence_group_id(item, seq) }
    end

    def own_origins(claim_id, seq)
      section_ids = (@placements[claim_id] || []).select { |p| p.counted_at?(seq) }.filter_map(&:section_id).uniq
      return Set.new if section_ids.empty?

      section_ids.filter_map { |id| @section_source[id] }.uniq.filter_map { |id| @sources[id] }
                 .filter_map { |source| Sources::Origin.key_for(source) }.to_set
    end

    # What `item.independence_group_at(seq)&.id` returns.
    def independence_group_id(item, seq)
      counted = (@assignments[item.id] || []).select { |a| a.counted_at?(seq) }
      return nil if counted.empty?

      top = counted.map(&:accepted_seq).max
      return item.independence_group_at(seq)&.id if counted.count { |a| a.accepted_seq == top } > 1

      group_id = counted.find { |a| a.accepted_seq == top }.independence_group_id
      @groups.include?(group_id) ? group_id : nil
    end

    # What `Tasks::Checks.for(claim_id, seq)` returns.
    def task_checks(claim_id, seq)
      tasks = (@tasks[claim_id] || []).index_by(&:id)
      return [] if tasks.empty?

      results = tasks.keys.flat_map { |id| @results[id] || [] }.select { |_, _, s| s <= seq }.sort_by { |_, _, s| s }
      results.filter_map do |id, task_id, _|
        next unless standing?(id, seq)
        next if @self_performed.include?(id)

        task = tasks[task_id]
        { "check" => Tasks::Checks::CHECK_FOR.fetch(task.task_type), "by" => task.id, "result_contribution_id" => id }
      end
    end

    # Contributions::Standing.standing, for every seq at once: accepted at or
    # before the seq, and not invalidated since that acceptance.
    def standing_timeline(ids)
      return {} if ids.empty?

      Contribution.where(action_type: %w[ACCEPT INVALIDATE]).where(seq: ..@max)
                  .where("payload->>'contribution_id' IN (?)", ids)
                  .pluck(Arel.sql("payload->>'contribution_id'"), :action_type, :seq)
                  .group_by(&:first)
    end

    def standing?(id, seq)
      entries = (@standing[id] || []).select { |_, _, s| s <= seq }
      accepted = entries.select { |_, a, _| a == "ACCEPT" }.map(&:last).max
      invalidated = entries.select { |_, a, _| a == "INVALIDATE" }.map(&:last).max
      accepted && (invalidated.nil? || invalidated < accepted)
    end
  end
end
