# frozen_string_literal: true

module Ledger
  # Content digests of projection tables, used to prove replay equivalence
  # (spec 07 Phase 2 #4) and, from Stage 6, snapshot digests.
  module TableDigest
    MODELS = (Contribution::PROJECTION_MODELS + %w[Quarantine ScoringModel Contributor AgentDelegation]).freeze

    def self.table(model)
      rows = model.order(:id).map { |row| row.attributes.as_json }
      Crypto::Hashing.json(rows)
    end

    def self.projections
      MODELS.to_h { |name| [ name.constantize.table_name, table(name.constantize) ] }
    end
  end
end
