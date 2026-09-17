# frozen_string_literal: true

module Ledger
  module Appliers
    # TAKEDOWN (spec 02 §5, constitution P-2): legally compelled removal of an
    # epistemic contribution's bytes, by a moderator, stating the date, the
    # legal basis, and a redaction manifest. The removal itself stays public.
    module Takedown
      extend Checks

      def self.authorize!(validated)
        reject("NOT_AUTHORIZED", "$.signer_key_id", "only a moderator key may take down") unless Governance::Moderators.moderator?(validated.contributor)
        p = validated.payload
        id = uuid!(p, "contribution_id")
        target = Contribution.find_by(id: id)
        reject("TARGET_UNKNOWN", path("contribution_id"), "no such contribution") if target.nil?
        reject("NOT_REDACTABLE", path("contribution_id"), "only epistemic contributions can be taken down") unless target.epistemic?
        reject("ALREADY_REDACTED", path("contribution_id"), "redacted at seq #{target.redacted_by_seq}") if target.redacted?
        string!(p, "legal_basis", max: 2_000)
        Date.iso8601(p["requested_at"].to_s)
        string_or_nil!(p, "requester")
        string_or_nil!(p, "note")
        Redaction.validate!(target, p["redaction_manifest"])
      rescue Date::Error
        reject("SCHEMA_INVALID", path("requested_at"), "expected YYYY-MM-DD")
      rescue Redaction::ManifestError => e
        reject(e.code, e.path, e.message)
      end

      def self.apply(c)
        Redaction.apply!(c)
      end
    end
  end
end
