# frozen_string_literal: true

module Contributions
  # A contribution's standing as of a seq, derived from the ACCEPT and
  # INVALIDATE entries that name it.
  #
  # Stage 39, finding 1. This was two queries per contribution, each filtering
  # `payload->>'contribution_id'` with no index to use, so Postgres walked the
  # `seq` index backwards and discarded everything that did not match: linear in
  # the length of the log, per call. One call was 73.7 ms on the dev node at
  # 5,165 contributions and 6,853 ms at 900,001, and the outline page made 780
  # of them. Two changes, both wanted, and both here:
  #
  # - `index_contributions_on_acceptance_target` makes one call a lookup.
  # - `accepted_set` answers for a whole collection in one query, because every
  #   caller had a collection in hand and asked per row.
  module Standing
    module_function

    def accepted_at?(contribution, seq)
      return false if contribution.seq > seq

      accepted_set([ contribution ], seq).include?(contribution.id)
    end

    # The ids, of those given, that stand accepted at this seq: accepted at or
    # before it, and not invalidated since that acceptance. One statement,
    # whatever the size of the set.
    def accepted_set(contributions, seq)
      eligible = contributions.reject { |c| c.seq > seq }
      return Set.new if eligible.empty?

      standing(eligible.map(&:id), seq)
    end

    def standing(ids, seq)
      rows = Contribution.where(action_type: %w[ACCEPT INVALIDATE]).where(seq: ..seq)
                         .where("payload->>'contribution_id' IN (?)", ids)
                         .group(Arel.sql("payload->>'contribution_id'"))
                         .pluck(Arel.sql("payload->>'contribution_id'"),
                                Arel.sql("MAX(seq) FILTER (WHERE action_type = 'ACCEPT')"),
                                Arel.sql("MAX(seq) FILTER (WHERE action_type = 'INVALIDATE')"))
      rows.filter_map { |id, accepted, invalidated| id if accepted && (invalidated.nil? || invalidated < accepted) }.to_set
    end
  end
end
