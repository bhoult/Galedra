# frozen_string_literal: true

module Tasks
  # Leasing (spec 04 §7): highest priority first, filtered by the delegation's
  # permissions, one slot per contributor and per principal, per-delegate daily
  # limits, per-type lease length. Returns nil when nothing is available.
  module Lease
    Rejected = Ledger::Rejected

    module_function

    def next(contributor:, delegation:, types: [], domains: [], target_id: nil, section_id: nil)
      principal = contributor.agent? ? delegation&.principal : contributor
      reject("DELEGATION_REQUIRED", "$.delegation_id", "agents lease under a delegation") if contributor.agent? && delegation.nil?
      reject("LEASE_LIMIT", "$", "daily task limit reached for this delegation") if delegation && over_daily_limit?(contributor, delegation)

      expire_stale!
      candidates(contributor, principal, delegation, types, domains, target_id, section_id).each do |task|
        next if task.open_slots <= 0
        # Stage 18: a principal never checks its own claim (04 §3.1, Article XI).
        next if own_target?(task, principal)
        # Stage 19: whoever asked for a blind check does not perform it.
        next if requested_by?(task, contributor, principal)

        assignment = TaskAssignment.create!(
          task: task, contributor: contributor, principal: principal, delegation_id: delegation&.id,
          lease_expires_at: Time.current + Types.lease_length(task.task_type), status: "LEASED"
        )
        Status.refresh!(task)
        return assignment
      end
      nil
    rescue ActiveRecord::RecordNotUnique
      # Two leases raced for the last slot; look again, a bounded number of times.
      (attempts = (attempts || 0) + 1) < 3 ? retry : nil
    end

    def candidates(contributor, principal, delegation, types, domains, target_id = nil, section_id = nil)
      scope = Task.where(status: %w[OPEN LEASED]).order(priority: :desc, created_at: :asc)
      scope = scope.where(target_id: target_id) if target_id
      scope = scope.where(section_id: subtree_ids(section_id)) if section_id
      allowed_types = delegation ? Array(delegation.permissions["allowed_task_types"]) : Types::ALL
      allowed_domains = delegation ? Array(delegation.permissions["domains"]) : Audits::Policy.domains
      types = types.presence || allowed_types
      domains = domains.presence || allowed_domains
      scope = scope.where(task_type: types & allowed_types, domain: domains & allowed_domains)
      taken = TaskAssignment.where(status: %w[LEASED SUBMITTED]).where("contributor_id = :c OR principal_contributor_id = :p", c: contributor.id, p: principal.id).select(:task_id)
      scope.where.not(id: taken).limit(50)
    end

    # Stage 21: a section means its whole subtree.
    def subtree_ids(section_id)
      section = Section.find_by(id: section_id)
      return [] if section.nil?

      ids = [ section.id ]
      frontier = [ section.id ]
      while frontier.any?
        frontier = Section.where(parent_id: frontier).pluck(:id)
        ids.concat(frontier)
      end
      ids
    end

    # The task's target stands on this principal's own say-so: recorded by it
    # (directly or through an agent) and not accepted by a different principal.
    # A proposal that another principal accepted (the demo's extracted claims)
    # is that principal's responsibility too, so its author may still work it.
    def own_target?(task, principal)
      return false if principal.nil?

      row = case task.target_type
      when "CLAIM" then Claim.find_by(id: task.target_id)
      when "INFERENCE" then Inference.find_by(id: task.target_id)
      else Source.find_by(id: task.target_id)
      end
      contribution = row&.contribution
      return false if contribution.nil? || ![ contribution.contributor_id, contribution.principal_contributor_id ].compact.include?(principal.id)

      accept = Contribution.where(action_type: "ACCEPT").where("payload->>'contribution_id' = ?", contribution.id).order(:seq).first
      accept.nil? || accept.contributor.nil? || accept.contributor.system? || [ accept.contributor_id, accept.principal_contributor_id ].compact.include?(principal.id)
    end

    def requested_by?(task, contributor, principal)
      creator = task.created_by_contributor_id
      return false if creator.nil?
      return true if creator == contributor.id || (principal && creator == principal.id)

      principal.present? && AgentDelegation.where(delegate_contributor_id: creator, principal_contributor_id: principal.id).exists?
    end

    def over_daily_limit?(contributor, delegation)
      limit = delegation.max_tasks_per_day
      return false if limit.nil?

      TaskAssignment.where(contributor_id: contributor.id).where("created_at >= ?", Time.current.beginning_of_day).count >= limit
    end

    def release(assignment)
      reject("LEASE_NOT_ACTIVE", "$", "lease is #{assignment.status.downcase}") unless assignment.status == "LEASED"
      assignment.update!(status: "RELEASED")
      Status.refresh!(assignment.task)
      assignment
    end

    def expire_stale!
      TaskAssignment.where(status: "LEASED").where("lease_expires_at <= ?", Time.current).find_each do |a|
        a.update!(status: "EXPIRED")
        Status.refresh!(a.task)
      end
    end

    def reject(code, path, detail)
      raise Rejected.new([ { code: code, path: path, detail: detail } ])
    end
  end

  module Status
    def self.refresh!(task)
      task.reload
      status = if task.status == "CANCELLED" then "CANCELLED"
      elsif task.submitted_assignments.count >= task.required_assignments then "COMPLETE"
      elsif task.open_slots <= 0 then "LEASED"
      else "OPEN"
      end
      task.update!(status: status) if task.status != status
      task
    end
  end
end
