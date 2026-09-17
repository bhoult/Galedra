# frozen_string_literal: true

module Ledger
  module Appliers
    # RELEASE_QUARANTINE (spec 05 §13): a moderator lifts a quarantine.
    module ReleaseQuarantine
      extend Checks

      def self.authorize!(validated)
        reject("NOT_AUTHORIZED", "$.signer_key_id", "only a moderator key may release a quarantine") unless Governance::Moderators.moderator?(validated.contributor)
        p = validated.payload
        id = uuid!(p, "quarantine_id")
        quarantine = ::Quarantine.find_by(id: id)
        reject("TARGET_UNKNOWN", path("quarantine_id"), "no such quarantine") if quarantine.nil?
        reject("ALREADY_RELEASED", path("quarantine_id"), "released at seq #{quarantine.released_seq}") if quarantine.released?
        string_or_nil!(p, "note")
      end

      def self.apply(c)
        quarantine = ::Quarantine.find(c.payload["quarantine_id"])
        quarantine.update!(released_seq: c.seq, release_contribution_id: c.id)
        Projections::Refresh.claim(Claim.find(quarantine.target_id)) if quarantine.target_type == "CLAIM"
      end
    end
  end
end
