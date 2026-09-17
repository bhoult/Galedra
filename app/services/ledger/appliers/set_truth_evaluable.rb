# frozen_string_literal: true

module Ledger
  module Appliers
    # SET_TRUTH_EVALUABLE (spec 02 §3.3, constitution P-3): a designation of
    # "not evaluable" is itself a contribution, always accepted by a different
    # principal, never automatically.
    module SetTruthEvaluable
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        current_claim!(p, "claim_id")
        evaluable = boolean!(p, "truth_evaluable")
        if evaluable
          reject("SCHEMA_INVALID", path("not_evaluable_reason"), "must be absent when truth_evaluable is true") unless p["not_evaluable_reason"].nil?
        else
          enum!(p, "not_evaluable_reason", Claim::NOT_EVALUABLE_REASONS)
        end
        string_or_nil!(p, "reason")
      end

      def self.auto_accept?(_validated) = false

      def self.apply(c)
        p = c.payload
        ClaimEvaluabilitySetting.create!(
          id: Ids.derive(c.id, "evaluability"), contribution_id: c.id, created_seq: c.seq,
          claim_id: p["claim_id"], truth_evaluable: p["truth_evaluable"], not_evaluable_reason: p["not_evaluable_reason"]
        )
      end
    end
  end
end
