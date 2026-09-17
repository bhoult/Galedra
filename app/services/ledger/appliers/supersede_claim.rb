# frozen_string_literal: true

module Ledger
  module Appliers
    # SUPERSEDE_CLAIM: a corrected claim replaces an active one (spec 02 §5).
    # The old row keeps its window; "superseded at S" is derived from the new
    # row being counted at S. Touching another principal's claim needs their
    # acceptance (02 §1.1a).
    module SupersedeClaim
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        current_claim!(p, "claim_id")
        CreateClaim.claim_fields!(p)
        string_or_nil!(p, "reason")
      end

      def self.warnings(validated) = CreateClaim.warnings(validated)

      def self.auto_accept?(validated)
        same_principal?(validated, Claim.find(validated.payload["claim_id"]))
      end

      def self.apply(c)
        CreateClaim.create_claim(c, c.payload, supersedes_claim_id: c.payload["claim_id"])
      end
    end
  end
end
