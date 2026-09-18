# frozen_string_literal: true

module Audits
  # Who may audit (spec 05 §8): a different principal from the target's, with
  # a track record in AUDIT for the domain, or a human at ESTABLISHED or above,
  # or a moderator (the bootstrap).
  module Eligibility
    module_function

    def check!(auditor, target, domain, seq)
      reject("NOT_AUTHORIZED", "$.signer_key_id", "only a registered contributor may audit") if auditor.nil?
      reject("NOT_AUTHORIZED", "$.signer_key_id", "the system key does not audit") if auditor.system?
      auditor_principal = auditor.agent? ? nil : auditor
      if target.principal_contributor_id && (auditor.id == target.contributor_id || auditor_principal&.id == target.principal_contributor_id)
        reject("NOT_AUTHORIZED", "$.payload.target_contribution_id", "a contribution cannot be audited by its own contributor or principal")
      end
      return if Governance::Moderators.moderator?(auditor)
      return if auditor.human? && Policy.config.fetch("established_tiers").include?(auditor.identity_tier)

      rep = Reputation::Calculate.call(contributor_id: auditor.id, task_type: "AUDIT", domain: domain, snapshot_seq: seq)
      return if BigDecimal(rep[:n]) >= Policy.config.fetch("auditor_min_n") && BigDecimal(rep[:mean]) >= BigDecimal(Policy.config.fetch("auditor_min_mean"))

      reject("NOT_ELIGIBLE", "$.signer_key_id", "auditors need n >= #{Policy.config['auditor_min_n']} and mean >= #{Policy.config['auditor_min_mean']} in AUDIT for #{domain}, or an ESTABLISHED+ human identity")
    end

    def reject(code, path, detail)
      raise Ledger::Rejected.new([ { code: code, path: path, detail: detail } ])
    end
  end
end
