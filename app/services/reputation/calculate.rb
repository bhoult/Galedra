# frozen_string_literal: true

module Reputation
  # Beta-Binomial reputation per (contributor, task_type, domain) from active
  # events at a snapshot (spec 05 §7). Events on a delegate roll up to its
  # principal; a contributor's own events and roll-ups both count for it.
  #
  # The per-result tally is opt-in and off by default in `call`, because only
  # the contributor page and the API display it while `Audits::Eligibility` and
  # `Audits::Sample` call this on every append and read nothing but `n` and
  # `mean`. Computing it there cost 366 million single-row audit lookups in one
  # 100k-claim seed; see `docs/profiler/2026-09-20-seed-write-path-decay.md`.
  module Calculate
    DELTAS = {
      "CONFIRMED" => [ "1.0", "0" ], "MINOR_ERROR" => [ "0.7", "0.3" ], "SUBSTANTIVE_ERROR" => [ "0", "1.0" ],
      "FABRICATION" => [ "0", "5.0" ], "UNRESOLVED" => [ "0", "0" ]
    }.freeze
    LIMITED_HISTORY_BELOW = 3

    module_function

    def deltas(result)
      DELTAS.fetch(result).map { |v| BigDecimal(v) }
    end

    def call(contributor_id:, task_type:, domain:, snapshot_seq:, counts: false)
      events = ReputationEvent.active_at(snapshot_seq).where(task_type: task_type, domain: domain)
                              .where("contributor_id = :id OR principal_contributor_id = :id", id: contributor_id)
      events = events.preload(:audit) if counts
      summarize(events, task_type, domain, counts: counts)
    end

    def buckets(contributor_id:, snapshot_seq:)
      events = ReputationEvent.active_at(snapshot_seq).preload(:audit)
                              .where("contributor_id = :id OR principal_contributor_id = :id", id: contributor_id)
      events.group_by { |e| [ e.task_type, e.domain ] }.map { |(t, d), es| summarize(es, t, d) }.sort_by { |b| [ b[:task_type], b[:domain] ] }
    end

    def summarize(events, task_type, domain, counts: true)
      alpha = BigDecimal(1) + events.sum(BigDecimal(0)) { |e| BigDecimal(e.alpha_delta.to_s) }
      beta = BigDecimal(1) + events.sum(BigDecimal(0)) { |e| BigDecimal(e.beta_delta.to_s) }
      n = alpha + beta - 2
      bucket = {
        task_type: task_type, domain: domain,
        alpha: Scoring::Decimal.fixed(alpha, 2), beta: Scoring::Decimal.fixed(beta, 2),
        mean: Scoring::Decimal.fixed(alpha.div(alpha + beta, Scoring::Decimal::PRECISION), 4),
        n: Scoring::Decimal.fixed(n, 2), limited_history: n < LIMITED_HISTORY_BELOW
      }
      return bucket unless counts

      # Callers that want this preload `:audit`; without it this line is one
      # query per event.
      bucket.merge(counts: events.map { |e| e.audit.result }.tally)
    end
  end
end
