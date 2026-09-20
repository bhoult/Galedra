# frozen_string_literal: true

namespace :tasks do
  desc "Cancel open tasks whose target is no longer current: bin/rails tasks:sweep_stale_targets (DRY_RUN=1)"
  task sweep_stale_targets: :environment do
    # Tasks::Lease cancels these where it finds them, and says why: a sweep on
    # every lease would load every open task, and this corpus already has
    # hundreds. That is right for the hot path and leaves the dead ones counted
    # until something happens to consider them — ten of them here, inflating the
    # open and answers_wanted totals an assistant reads to decide what is left
    # (docs/experiments/2026-09-20-second-connector-run.md). Batch work belongs
    # in a batch, so this is the same rule applied where it costs nothing.
    dry = ENV["DRY_RUN"] == "1"
    seq = Contribution.maximum(:seq) || 0
    stale = Task.where(status: %w[OPEN LEASED], target_type: "CLAIM")
                .where(target_id: Claim.where.not(status: "ACTIVE").select(:id))
                .reject { |t| Claim.find_by(id: t.target_id)&.current_at?(seq) }

    stale.each { |t| t.update!(status: "CANCELLED", cancelled_reason: Tasks::Lease::TARGET_NOT_CURRENT) } unless dry
    puts "#{dry ? 'would cancel' : 'cancelled'} #{stale.size} task(s) whose target is no longer current"
  end

  desc "Recompute stored priority for open tasks: bin/rails tasks:reprioritise (DRY_RUN=1 to count only)"
  task reprioritise: :environment do
    # Tasks::Create stamps priority at creation, so a change to the heuristic or
    # its damping reaches new tasks only. When NOT_APPLICABLE_FACTOR was added,
    # 740 tasks already on the board kept their old priorities and went on being
    # handed out ahead of work that can move
    # (docs/experiments/2026-09-20-second-connector-run.md, finding 2).
    #
    # Idempotent: the priority is recomputed from the log at the task's own
    # issued_seq, so running this twice writes the same number. Priority is a
    # board heuristic and never a score input, so rewriting it changes no
    # epistemic value.
    #
    # Scoped to targets no model scores, and that scoping is the point. A full
    # recompute also re-stamps every other task under whichever model is default
    # now, which on this node moved 181 priorities by 2/3 purely because the
    # default went from 0.1.0 to 0.2.0. Switching what a visitor sees is a
    # decision and not a side effect of a rake task, so this task refuses to make
    # it. An unscoreable claim carries no probability under any model, so its
    # heuristic is model-independent and only the damping moves.
    dry = ENV["DRY_RUN"] == "1"
    model = Scoring::Registry.default_model
    unscored = model&.config&.fetch("scored_types", nil) || Claim::TYPES
    scope = Task.where(status: %w[OPEN LEASED], target_type: "CLAIM")
                .where(target_id: Claim.where.not(claim_type: unscored).select(:id))
    changed = 0
    total = scope.count

    scope.find_each.with_index do |task, i|
      before = task.priority
      after = BigDecimal(Tasks::Create.priority_for(task.task_type, task.target, task.issued_seq))
      next if before == after

      changed += 1
      task.update!(priority: after) unless dry
      puts "  #{task.task_type} #{task.id}  #{before.to_s('F')} -> #{after.to_s('F')}" if changed <= 10
    rescue ActiveRecord::RecordNotFound
      # A task whose target has since been taken down; leave it alone.
      next
    ensure
      print "\r  #{i + 1}/#{total}" if ((i + 1) % 50).zero?
    end

    puts "\n#{dry ? 'would change' : 'changed'} #{changed} of #{total} open tasks"
  end
end
