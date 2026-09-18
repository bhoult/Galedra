# frozen_string_literal: true

module Ledger
  module Appliers
    # AUDIT (spec 05 §9): an eligible, different principal evaluates a prior
    # contribution. Effects: CONFIRMED counts toward clearing provisional;
    # SUBSTANTIVE_ERROR and FABRICATION invalidate the target through a
    # system-signed INVALIDATE; UNRESOLVED marks it CHALLENGED and schedules a
    # second audit. A RE_AUDIT targets an audit; if it disagrees, the first
    # audit is invalidated and the original target restored by a new ACCEPT.
    module Audit
      extend Checks

      def self.authorize!(validated)
        p = validated.payload
        id = uuid!(p, "target_contribution_id")
        target = Contribution.find_by(id: id)
        reject("TARGET_UNKNOWN", path("target_contribution_id"), "no such contribution") if target.nil?
        type = enum!(p, "audit_type", ::Audit::TYPES)
        enum!(p, "result", ::Audit::RESULTS)
        integer_or_nil!(p, "effort_seconds")
        string_or_nil!(p, "note")
        if target.action_type == "AUDIT"
          reject("SCHEMA_INVALID", path("audit_type"), "an audit of an audit is a RE_AUDIT") unless type == "RE_AUDIT"
          first = ::Audit.find_by(contribution_id: target.id)
          reject("TARGET_INVALIDATED", path("target_contribution_id"), "that audit was already overturned") if first.nil? || first.invalidated?
        else
          reject("SCHEMA_INVALID", path("audit_type"), "RE_AUDIT targets an audit") if type == "RE_AUDIT"
          reject("NOT_AUDITABLE", path("target_contribution_id"), "only epistemic contributions and audits are audited") unless target.epistemic?
          reject("TARGET_INVALIDATED", path("target_contribution_id"), "contribution is invalidated") if target.current_status == Contribution::INVALIDATED
        end
        _, domain = Audits::Bucket.for(target)
        Audits::Eligibility.check!(validated.contributor, target, domain, Contribution.maximum(:seq))
      end

      def self.apply(c)
        p = c.payload
        target = Contribution.find(p["target_contribution_id"])
        re_audit = target.action_type == "AUDIT"
        first_audit = re_audit ? ::Audit.find_by!(contribution_id: target.id) : nil
        task_type, domain = re_audit ? [ "AUDIT", first_audit.domain ] : Audits::Bucket.for(target)

        audit = ::Audit.create!(
          id: Ids.derive(c.id, "audit"), contribution_id: c.id, created_seq: c.seq,
          target_contribution_id: target.id, auditor_contributor_id: c.contributor_id,
          audit_type: p["audit_type"], result: p["result"], effort_seconds: p["effort_seconds"], note: p["note"],
          task_type: task_type, domain: domain
        )
        record_reputation(c, audit, target, task_type, domain)

        re_audit ? apply_re_audit(c, audit, first_audit) : apply_effect(c, audit, target)
      end

      def self.record_reputation(c, audit, target, task_type, domain)
        alpha, beta = Reputation::Calculate.deltas(audit.result)
        ReputationEvent.create!(
          id: Ids.derive(c.id, "reputation_event"), contribution_id: c.id, created_seq: c.seq,
          contributor_id: target.contributor_id, task_type: task_type, domain: domain, audit_id: audit.id,
          principal_contributor_id: (target.principal_contributor_id if target.principal_contributor_id != target.contributor_id),
          alpha_delta: alpha, beta_delta: beta
        )
      end

      def self.apply_effect(c, audit, target)
        case audit.result
        when "SUBSTANTIVE_ERROR", "FABRICATION"
          return if target.current_status == Contribution::INVALIDATED

          envelope = Contributions::Envelope.build(
            action_type: "INVALIDATE", key_pair: Crypto::SystemKey.key_pair,
            payload: { "contribution_id" => target.id, "reason" => "AUDIT #{audit.result} at seq #{c.seq}", "audit_contribution_id" => c.id }
          )
          Append.call(envelope, custody: Crypto::Custody::SYSTEM)
        when "UNRESOLVED"
          target.update!(current_status: Contribution::CHALLENGED) if target.epistemic?
          Audits::Sample.reschedule!(target, c.seq)
        when "CONFIRMED"
          target.update!(current_status: Contribution::ACCEPTED) if target.current_status == Contribution::CHALLENGED
        end
      end

      # A disagreeing re-audit invalidates the first audit and its reputation
      # event, and restores the original target if the first audit had it invalidated.
      def self.apply_re_audit(c, re_audit, first_audit)
        return unless re_audit.disagrees?

        first_audit.update!(invalidated_seq: c.seq)
        ReputationEvent.where(audit_id: first_audit.id).update_all(invalidated_seq: c.seq)
        original = first_audit.target_contribution
        return unless original.current_status == Contribution::INVALIDATED &&
                      Contribution.where(action_type: "INVALIDATE").where("payload->>'audit_contribution_id' = ?", first_audit.contribution_id).exists?

        envelope = Contributions::Envelope.build(
          action_type: "ACCEPT", key_pair: Crypto::SystemKey.key_pair,
          payload: { "contribution_id" => original.id, "basis" => "RESTORED_AFTER_RE_AUDIT", "re_audit_contribution_id" => c.id }
        )
        Append.call(envelope, custody: Crypto::Custody::SYSTEM)
      end
    end
  end
end
