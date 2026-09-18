# frozen_string_literal: true

module Audits
  # Deterministic, anchored audit sampling (spec 05 §9). Every input is
  # evaluated as of the contribution's own seq and stored, and the decision is
  # sha256(entry_hash + policy_version) < probability × 2^256, so anyone can
  # recompute whether a contribution should have been sampled.
  module Sample
    TWO_256 = 2**256

    module_function

    def schedule!(contribution)
      return if AuditSchedule.exists?(contribution_id: contribution.id)

      inputs = inputs_for(contribution)
      probability = probability_for(inputs)
      AuditSchedule.create!(
        id: Ledger::Ids.derive(contribution.id, "audit_schedule"), contribution_id: contribution.id,
        evaluated_at_seq: contribution.seq, policy_version: Policy.version, inputs: inputs,
        audit_probability: Scoring::Decimal.fixed(probability, 4), sampled: sampled?(contribution.entry_hash, probability)
      )
    end

    def force!(contribution, by_seq)
      schedule = AuditSchedule.find_by(contribution_id: contribution.id) || schedule!(contribution)
      schedule.update!(forced_by_seq: by_seq)
    end

    def reschedule!(contribution, by_seq)
      schedule = AuditSchedule.find_by(contribution_id: contribution.id) || schedule!(contribution)
      schedule.update!(rescheduled_by_seq: by_seq)
    end

    def sampled?(entry_hash, probability)
      Digest::SHA256.hexdigest(entry_hash + Policy.version).to_i(16) < (probability * TWO_256).floor
    end

    def inputs_for(contribution)
      seq = contribution.seq
      task_type, domain = Bucket.for(contribution)
      rep = Reputation::Calculate.call(contributor_id: contribution.contributor_id, task_type: task_type, domain: domain, snapshot_seq: seq - 1)
      {
        "n" => rep[:n], "mean" => rep[:mean], "task_type" => task_type, "domain" => domain,
        "downstream_count" => Status.downstream_count(contribution.id, seq),
        "outcome_is_unusual" => unusual?(contribution)
      }
    end

    def probability_for(inputs)
      c = Policy.config
      p = BigDecimal(c["base_rate"])
      p *= BigDecimal(c["new_identity_factor"]) if BigDecimal(inputs["n"]) < c["new_identity_n"]
      p *= BigDecimal(c["low_reliability_factor"]) if BigDecimal(inputs["mean"]) < BigDecimal(c["low_reliability_mean"])
      p *= BigDecimal(1) + BigDecimal(inputs["downstream_count"]).div(BigDecimal(c["impact_divisor"]), Scoring::Decimal::PRECISION)
      p *= BigDecimal(c["unusual_factor"]) if inputs["outcome_is_unusual"]
      [ p, BigDecimal(1) ].min
    end

    # P0 definition (05 §9): the outcome disagrees with the target claim's
    # state just before this contribution. For direct links: a SUPPORT link on
    # a claim with contradiction groups and no support, or a CONTRADICT link on
    # a claim with two or more support groups.
    def unusual?(contribution)
      return false unless %w[LINK_EVIDENCE SUPERSEDE_LINK].include?(contribution.action_type)

      link = EvidenceClaimLink.find_by(contribution_id: contribution.id)
      model = Scoring::Registry.default_model_at(contribution.seq)
      return false if link.nil? || model.nil? || contribution.seq.zero?

      result = Scoring::Score.call(link.claim, contribution.seq - 1, model)
      case link.direction
      when "SUPPORT" then result.contradict_groups >= 1 && result.support_groups.zero?
      when "CONTRADICT" then result.support_groups >= 2
      else false
      end
    rescue ActiveRecord::RecordNotFound
      false
    end
  end

  # The reputation bucket a contribution belongs to (spec 02 §3.4): its task's
  # type and domain, or MANUAL × general outside a task (tasks arrive in Stage 8).
  module Bucket
    module_function

    def for(contribution)
      task = contribution.task_id && Tasks::Lookup.for(contribution.task_id)
      task ? [ task[:task_type], task[:domain] ] : [ Policy.manual_task_type, Policy.default_domain ]
    end
  end
end
