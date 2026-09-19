# frozen_string_literal: true

module Claims
  # Trigram near-duplicate suggestions (spec 02 §3.3, 06 §7). Candidates only:
  # nothing here ever merges, and similarity is never evidence weight.
  module Duplicates
    THRESHOLD = 0.3
    LIMIT = 10

    def self.candidates(text, exclude_id: nil, limit: LIMIT, threshold: THRESHOLD)
      # Bound, not interpolated. Quoting the text was correct, but a quoted
      # literal built by hand is one careless edit from not being, and this
      # takes contributor-supplied text (security audit, 2026-09-19).
      similarity = ActiveRecord::Base.sanitize_sql_array([ "similarity(canonical_text, ?)", text ])
      scope = Claim.live.accepted.where.not(id: Governance::Quarantines.quarantined_claim_ids)
                   .where("similarity(canonical_text, ?) >= ?", text, threshold)
      scope = scope.where.not(id: exclude_id) if exclude_id
      scope.select(Arel.sql("claims.*, #{similarity} AS similarity"))
           .order(Arel.sql("similarity DESC, created_seq ASC")).limit(limit)
    end
  end
end
