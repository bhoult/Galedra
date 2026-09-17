# frozen_string_literal: true

module Ledger
  module Appliers
    # MERGE_CLAIMS (spec 02 §3.3): explicit, attributed, accepted, and reversed
    # by INVALIDATE-ing this contribution. Similarity only ever suggests.
    module MergeClaims
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        from = current_claim!(p, "from_claim_id")
        into = current_claim!(p, "into_claim_id")
        reject("SCHEMA_INVALID", path("into_claim_id"), "must differ from from_claim_id") if from.id == into.id
        string_or_nil!(p, "reason")
      end

      def self.auto_accept?(validated)
        p = validated.payload
        same_principal?(validated, Claim.find(p["from_claim_id"]), Claim.find(p["into_claim_id"]))
      end

      def self.apply(c)
        p = c.payload
        ClaimMerge.create!(
          id: Ids.derive(c.id, "merge"), contribution_id: c.id, created_seq: c.seq,
          from_claim_id: p["from_claim_id"], into_claim_id: p["into_claim_id"]
        )
      end
    end
  end
end
