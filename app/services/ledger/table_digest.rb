# frozen_string_literal: true

module Ledger
  # Content digests of projection tables, used to prove replay equivalence
  # (spec 07 Phase 2 #4) and, from Stage 6, snapshot digests.
  module TableDigest
    MODELS = (Contribution::PROJECTION_MODELS + %w[Quarantine ScoringModel Audit AuditSchedule ReputationEvent Contributor AgentDelegation]).freeze

    # Cache metadata, digested no more than `claim_scores` is: Stage 38's
    # `scored_inputs_seq` is a hint about when a score last *could* have moved,
    # rebuilt by replay and discardable without loss. Including it would change
    # every digest ever taken of `claims` for something that carries no claim.
    DERIVED = { "claims" => %w[scored_inputs_seq] }.freeze

    def self.table(model)
      derived = DERIVED[model.table_name] || []
      rows = model.order(:id).map { |row| row.attributes.as_json.except(*derived) }
      Crypto::Hashing.json(rows)
    end

    def self.projections
      MODELS.to_h { |name| [ name.constantize.table_name, table(name.constantize) ] }
    end
  end
end
