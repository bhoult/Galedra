# frozen_string_literal: true

module Tasks
  # Leasing (spec 04 §7): highest priority first, filtered by the delegation's
  # permissions, one slot per contributor and per principal, per-delegate daily
  # limits, per-type lease length. Returns nil when nothing is available.
  module Lease
    Rejected = Ledger::Rejected

    module_function

    def next(contributor:, delegation:, types: [], domains: [])
      principal = contributor.agent? ? delegation&.principal : contributor
      reject("DELEGATION_REQUIRED", "$.delegation_id", "agents lease under a delegation") if contributor.agent? && delegation.nil?
      reject("LEASE_LIMIT", "$", "daily task limit reached for this delegation") if delegation && over_daily_limit?(contributor, delegation)

      expire_stale!
      candidates(contributor, principal, delegation, types, domains).each do |task|
        next if task.open_slots <= 0

        assignment = TaskAssignment.create!(
          task: task, contributor: contributor, principal: principal, delegation_id: delegation&.id,
          lease_expires_at: Time.current + Types.lease_length(task.task_type), status: "LEASED"
        )
        Status.refresh!(task)
        return assignment
      end
      nil
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def candidates(contributor, principal, delegation, types, domains)
      scope = Task.where(status: %w[OPEN LEASED]).order(priority: :desc, created_at: :asc)
      allowed_types = delegation ? Array(delegation.permissions["allowed_task_types"]) : Types::ALL
      allowed_domains = delegation ? Array(delegation.permissions["domains"]) : Audits::Policy.domains
      types = types.presence || allowed_types
      domains = domains.presence || allowed_domains
      scope = scope.where(task_type: types & allowed_types, domain: domains & allowed_domains)
      taken = TaskAssignment.where(status: %w[LEASED SUBMITTED]).where("contributor_id = :c OR principal_contributor_id = :p", c: contributor.id, p: principal.id).select(:task_id)
      scope.where.not(id: taken).limit(50)
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
