# frozen_string_literal: true

module Governance
  # The public moderation log (spec 05 §13, 06 §5): every quarantine, release,
  # takedown, suspension, and revocation, with the moderator key, the reason
  # category, and the appeal status. Moderator actions are contributions like
  # any other, so this is a view over the log.
  module ModerationLog
    MODERATION_ACTIONS = %w[QUARANTINE RELEASE_QUARANTINE TAKEDOWN].freeze
    SUSPENSION_ACTIONS = %w[REVOKE_KEY REVOKE_DELEGATION].freeze

    def self.entries(after_seq: -1, limit: 100)
      scope = Contribution.where(action_type: MODERATION_ACTIONS + SUSPENSION_ACTIONS).where("seq > ?", after_seq).in_order
      scope.filter_map { |c| entry(c) }.first(limit)
    end

    def self.entry(c)
      case c.action_type
      when "QUARANTINE"
        q = Quarantine.find_by(contribution_id: c.id)
        base(c, "QUARANTINE", q&.target_type, q&.target_id, q&.reason, appeal_status: q&.released? ? "RELEASED" : "OPEN")
      when "RELEASE_QUARANTINE"
        q = Quarantine.find_by(id: c.payload&.dig("quarantine_id"))
        base(c, "RELEASE_QUARANTINE", q&.target_type, q&.target_id, q&.reason, appeal_status: "RELEASED")
      when "TAKEDOWN"
        base(c, "TAKEDOWN", "CONTRIBUTION", c.payload&.dig("contribution_id"), "LEGAL_REMOVAL",
             legal_basis: c.payload&.dig("legal_basis"), requested_at: c.payload&.dig("requested_at"), appeal_status: "NONE")
      else
        return nil unless Moderators.moderator?(c.contributor)

        target = c.action_type == "REVOKE_KEY" ? c.payload&.dig("key_id") : c.payload&.dig("delegation_id")
        base(c, "SUSPENSION", c.action_type == "REVOKE_KEY" ? "KEY" : "DELEGATION", target, "SUSPENSION", appeal_status: "OPEN")
      end
    end

    def self.base(c, action, target_type, target_id, reason, **extra)
      {
        seq: c.seq, contribution_id: c.id, action: action, at: c.received_at_rfc3339,
        moderator_key_id: c.signer_key_id, moderator_display_name: c.contributor&.display_name,
        target_type: target_type, target_id: target_id, reason: reason, note: c.payload&.dig("note")
      }.merge(extra)
    end
  end
end
