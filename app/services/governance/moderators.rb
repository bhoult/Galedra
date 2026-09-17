# frozen_string_literal: true

module Governance
  # Who may quarantine, take down, suspend, and invalidate on the ledger's
  # behalf. Appointment is outside the log (spec 09 §15 leaves it open):
  # key ids in LEDGER_MODERATOR_KEY_IDS, plus server-custodied keys of users
  # flagged moderator. Published by /api/v1/meta so the power is visible.
  module Moderators
    ENV_KEY = "LEDGER_MODERATOR_KEY_IDS"

    def self.configured_key_ids
      ENV.fetch(ENV_KEY, "").split(",").map(&:strip).reject(&:empty?)
    end

    def self.key_ids
      configured_key_ids | Contributor.joins(custodied_key: :user).where(users: { moderator: true }).pluck(:key_id)
    end

    def self.moderator?(contributor)
      return false if contributor.nil? || contributor.system? || contributor.revoked?

      configured_key_ids.include?(contributor.key_id) || contributor.custodied_key&.user&.moderator? || false
    end
  end
end
