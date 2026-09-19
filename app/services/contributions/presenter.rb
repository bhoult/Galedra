# frozen_string_literal: true

module Contributions
  # JSON shapes for the log endpoints (spec 06 §2). Entries carry everything a
  # third party needs to mirror and verify the chain.
  module Presenter
    def self.entry(c, withheld_ids: Governance::Quarantines.withheld_contribution_ids)
      withheld = withheld_ids.include?(c.id)
      {
        id: c.id, seq: c.seq, action_type: c.action_type, action_class: c.action_class,
        signer_key_id: c.signer_key_id, contributor_id: c.contributor_id, custody: c.custody, visibility: c.visibility,
        current_status: c.current_status, task_id: c.task_id, redacted_by_seq: c.redacted_by_seq,
        client_created_at: c.client_created_at.utc.iso8601, received_at: c.received_at_rfc3339,
        prev_hash: c.prev_hash, envelope_hash: c.envelope_hash, entry_hash: c.entry_hash,
        server_signature: c.server_signature, envelope: withheld ? nil : c.envelope,
        withheld: withheld ? { reason: "QUARANTINE", appeal_path: Governance::Quarantines::APPEAL_PATH } : nil
      }.then { |h| withheld ? h : h.except(:withheld) }
    end

    def self.summary(c)
      entry(c, withheld_ids: []).except(:envelope, :withheld)
    end

    def self.audits(c)
      Audit.where(target_contribution_id: c.id).order(:created_seq).map { |a| audit(a) }
    end

    def self.audit(a)
      { id: a.id, seq: a.created_seq, contribution_id: a.contribution_id, auditor_key_id: a.auditor.key_id,
        audit_type: a.audit_type, result: a.result, task_type: a.task_type, domain: a.domain, note: a.note,
        effort_seconds: a.effort_seconds, invalidated_seq: a.invalidated_seq,
        re_audits: Audit.where(target_contribution_id: a.contribution_id).order(:created_seq).map { |r| r.slice(:id, :result, :created_seq, :invalidated_seq) } }
    end

    def self.audit_schedule(c)
      s = AuditSchedule.find_by(contribution_id: c.id)
      return nil if s.nil?

      { evaluated_at_seq: s.evaluated_at_seq, policy_version: s.policy_version, inputs: s.inputs,
        audit_probability: s.audit_probability, sampled: s.sampled, forced_by_seq: s.forced_by_seq, rescheduled_by_seq: s.rescheduled_by_seq }
    end

    # Every log entry that changed this contribution's standing, in seq order.
    def self.status_history(c)
      events = [ { seq: c.seq, event: "APPENDED", status: c.control? ? Contribution::ACCEPTED : Contribution::PENDING } ]
      Contribution.where(action_type: %w[ACCEPT INVALIDATE]).where("payload->>'contribution_id' = ?", c.id).in_order.each do |e|
        events << { seq: e.seq, event: e.action_type, by: e.signer_key_id, basis: e.payload["basis"], reason: e.payload["reason"] }
      end
      Audit.where(target_contribution_id: c.id).order(:created_seq).each do |a|
        events << { seq: a.created_seq, event: "AUDIT", result: a.result, by: a.auditor.key_id, overturned_seq: a.invalidated_seq }
      end
      Contribution.where(action_type: "REVOKE_KEY").where("payload->>'key_id' = ?", c.signer_key_id)
                  .where("(payload->>'compromised_since')::bigint <= ?", c.seq).in_order.each do |r|
        events << { seq: r.seq, event: "CHALLENGED_BY_REVOCATION", by: r.signer_key_id }
      end
      events.sort_by { |e| e[:seq] }
    end
  end
end
