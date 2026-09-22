# frozen_string_literal: true

module Tasks
  # Leasing (spec 04 §7): highest priority first, filtered by the delegation's
  # permissions, one slot per contributor and per principal, per-delegate daily
  # limits, per-type lease length. Returns nil when nothing is available.
  module Lease
    Rejected = Ledger::Rejected

    # Stage 34: checks a principal may perform on its own claim, recorded as
    # self-performed and kept out of the scorer entirely.
    #
    # 04 §3.1 forbids exactly two things — auditing your own contribution, and
    # accepting your own proposed claim — and neither is a task type. The guard
    # below used to cover every type, which meant a person who outlined a source
    # alone could never finish checking it and had to wait for a stranger.
    # Independence grouping and inference review stay closed: both are structural
    # judgements about one's own reasoning, where a second reader is the point.
    SELF_CHECKABLE = %w[EVIDENCE_VERIFICATION OPPOSING_EVIDENCE_SEARCH QUALIFIER_CHECK].freeze

    # A task whose claim has since been merged or superseded can never be
    # submitted: the appliers refuse it with CLAIM_NOT_CURRENT. Releasing it
    # returns it to the head of the queue, so it is handed out again and again
    # and blocks every filter that reaches it. Reported by an assistant that was
    # given the same unworkable task three times.
    TARGET_NOT_CURRENT = "TARGET_NOT_CURRENT"

    module_function

    def next(contributor:, delegation:, types: [], domains: [], target_id: nil, section_id: nil, settleable: false)
      principal = contributor.agent? ? delegation&.principal : contributor
      reject("DELEGATION_REQUIRED", "$.delegation_id", "agents lease under a delegation") if contributor.agent? && delegation.nil?
      reject("LEASE_LIMIT", "$", "hourly task limit reached for this delegation") if delegation && over_hourly_limit?(contributor, delegation)

      expire_stale!
      candidates(contributor, principal, delegation, types, domains, target_id, section_id, settleable).each do |task|
        next if task.open_slots <= 0
        # Cancelled where it is found rather than swept in a batch: the sweep
        # would load every open task on every lease, and this corpus already has
        # hundreds. Reversible in the sense that matters — if the merge is later
        # invalidated, the claim is current again and new tasks open for it.
        if stale_target?(task)
          task.update!(status: "CANCELLED", cancelled_reason: TARGET_NOT_CURRENT)
          next
        end
        own = own_target?(task, principal)
        # Stage 34: own work is checkable for the types above, and recorded as
        # self-performed so nothing downstream can mistake it for independent.
        next if own && !SELF_CHECKABLE.include?(task.task_type)
        # Stage 19: whoever asked for a blind check does not perform it. Only a
        # check someone deliberately requested; the verification tasks that open
        # alongside a recording are not a request to be honoured against its own
        # author (Stage 34).
        next if task.blind_requested? && requested_by?(task, contributor, principal)

        assignment = TaskAssignment.create!(
          task: task, contributor: contributor, principal: principal, delegation_id: delegation&.id,
          lease_expires_at: Time.current + Types.lease_length(task.task_type), status: "LEASED",
          self_performed: own
        )
        Status.refresh!(task)
        return assignment
      end
      nil
    rescue ActiveRecord::RecordNotUnique
      # Two leases raced for the last slot; look again, a bounded number of times.
      (attempts = (attempts || 0) + 1) < 3 ? retry : nil
    end

    # `settleable` restricts to claims a model actually scores. A claim whose
    # type is not in scored_types is NOT_APPLICABLE by construction, so a
    # qualifier check or an opposing-evidence search on it has its outcome fixed
    # before the work starts. An assistant could see this happening and had no
    # way to ask for anything else: next_task filtered on task type and domain,
    # and neither can express "a claim whose state can change". It reported the
    # problem and was handed two more
    # (docs/experiments/2026-09-20-second-connector-run.md, finding 2).
    def candidates(contributor, principal, delegation, types, domains, target_id = nil, section_id = nil, settleable = false)
      scope = Task.where(status: %w[OPEN LEASED]).order(priority: :desc, created_at: :asc)
      scope = scope.where(target_id: target_id) if target_id
      scope = scope.where(section_id: subtree_ids(section_id)) if section_id
      scope = scope.where(target_type: "CLAIM", target_id: scoreable_claim_ids) if settleable
      allowed_types = delegation ? Array(delegation.permissions["allowed_task_types"]) : Types::ALL
      allowed_domains = delegation ? Array(delegation.permissions["domains"]) : Audits::Policy.domains
      types = types.presence || allowed_types
      domains = domains.presence || allowed_domains
      scope = scope.where(task_type: types & allowed_types, domain: domains & allowed_domains)
      kin = kin_principal_ids(principal)
      taken = TaskAssignment.where(status: %w[LEASED SUBMITTED])
                            .where("contributor_id = :c OR principal_contributor_id IN (:p)", c: contributor.id, p: kin).select(:task_id)
      scope.where.not(id: taken).limit(50)
    end

    # The claim types the default model scores. Anything else finishes as
    # NOT_APPLICABLE with reason NOT_SCORED_BY_MODEL, carrying no probability
    # (Invariant 5), so no evidence can move it.
    def scoreable_claim_ids
      model = Scoring::Registry.default_model
      types = model&.config&.fetch("scored_types", nil) || Claim::TYPES
      Claim.where(claim_type: types).select(:id)
    end

    # Stage 21: a section means its whole subtree.
    # A principal, plus every principal that took its token from the same place.
    #
    # `introduce_yourself` gives each self-minted token a fresh anonymous
    # principal, so five tokens taken from one address are five principals — and
    # the three independent answers a task wants would be three of them, making
    # one actor into a quorum. The mint records where it came from precisely so
    # this can be asked (Article XII: resist capture). Adopted and account-held
    # tokens carry no mint source and are unaffected.
    def kin_principal_ids(principal)
      keys = AssistantToken.where(principal_contributor_id: principal.id)
                           .where.not(mint_source_key: nil).distinct.pluck(:mint_source_key)
      return [ principal.id ] if keys.empty?

      ([ principal.id ] + AssistantToken.where(mint_source_key: keys).distinct.pluck(:principal_contributor_id)).uniq
    end

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
    # This principal has already submitted a result on this task. A principal
    # answers each task once, so this is also the reason nothing more can be
    # added to that answer by leasing it again.
    def answered_by?(task, principal)
      return false if principal.nil?

      TaskAssignment.where(task_id: task.id, status: "SUBMITTED")
                    .where("contributor_id = :c OR principal_contributor_id IN (:p)", c: principal.id, p: kin_principal_ids(principal)).exists?
    end

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

    # True when the task targets a claim that is no longer current at the head.
    def stale_target?(task)
      return false unless task.target_type == "CLAIM"

      claim = Claim.find_by(id: task.target_id)
      seq = Contribution.maximum(:seq)
      claim.nil? || seq.nil? || !claim.current_at?(seq)
    end

    def requested_by?(task, contributor, principal)
      creator = task.created_by_contributor_id
      return false if creator.nil?
      return true if creator == contributor.id || (principal && creator == principal.id)

      principal.present? && AgentDelegation.where(delegate_contributor_id: creator, principal_contributor_id: principal.id).exists?
    end

    def over_hourly_limit?(contributor, delegation)
      limit = delegation.max_tasks_per_hour
      return false if limit.nil?

      TaskAssignment.where(contributor_id: contributor.id).where("created_at >= ?", 1.hour.ago).count >= limit
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
end
