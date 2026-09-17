# frozen_string_literal: true

module Claims
  # Trigram near-duplicate suggestions (spec 02 §3.3, 06 §7). Candidates only:
  # nothing here ever merges, and similarity is never evidence weight.
  module Duplicates
    THRESHOLD = 0.3
    LIMIT = 10

    def self.candidates(text, exclude_id: nil, limit: LIMIT, threshold: THRESHOLD)
      quoted = Claim.connection.quote(text)
      scope = Claim.live.accepted.where.not(id: Governance::Quarantines.quarantined_claim_ids)
                   .where("similarity(canonical_text, #{quoted}) >= ?", threshold)
      scope = scope.where.not(id: exclude_id) if exclude_id
      scope.select("claims.*, similarity(canonical_text, #{quoted}) AS similarity")
           .order(Arel.sql("similarity DESC, created_seq ASC")).limit(limit)
    end
  end
end
