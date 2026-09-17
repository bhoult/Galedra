# frozen_string_literal: true

module Contributions
  # JSON shapes for the log endpoints (spec 06 §2). Entries carry everything a
  # third party needs to mirror and verify the chain.
  module Presenter
    def self.entry(c, withheld_ids: Governance::Quarantines.withheld_contribution_ids)
      withheld = withheld_ids.include?(c.id)
      {
        id: c.id, seq: c.seq, action_type: c.action_type, action_class: c.action_class,
        signer_key_id: c.signer_key_id, contributor_id: c.contributor_id, custody: c.custody,
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
  end
end
