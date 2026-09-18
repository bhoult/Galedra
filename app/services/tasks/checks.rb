# frozen_string_literal: true

module Tasks
  # Task-derived review checks for a claim as of a seq (spec 03 §8): accepted
  # OPPOSING_EVIDENCE_SEARCH, SOURCE_INDEPENDENCE_CHECK, and QUALIFIER_CHECK
  # results. Tasks arrive in Stage 8; until then no task check is satisfied.
  module Checks
    def self.for(_claim_id, _seq)
      []
    end

    # Whether an accepted opposing search covers a contribution's claims (05 §10).
    def self.opposing_search_done?(_contribution_id, _seq)
      false
    end
  end
end
