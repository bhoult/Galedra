# frozen_string_literal: true

module RequestMetrics
  # Retention for the request metrics (Stage 40), two ways.
  #
  # By age, because a month-old timing describes a corpus and a codebase that no
  # longer exist. And by action, because the moment a slow path is fixed its old
  # rows stop being evidence and start being a lie about where the time goes —
  # `metrics:clear` is meant to be run as part of fixing something, not as
  # housekeeping.
  #
  # Nothing epistemic is lost either way: these tables are derived operational
  # data, outside the log and outside Ledger::TableDigest.
  module Prune
    DEFAULT_KEEP_DAYS = 30

    module_function

    def call(keep_days: DEFAULT_KEEP_DAYS)
      cutoff = keep_days.days.ago
      { keep_days: keep_days,
        tallies: RequestTally.where(hour: ...cutoff).delete_all,
        samples: RequestSample.where(recorded_at: ...cutoff).delete_all }
    end

    def clear(action)
      { action: action,
        tallies: RequestTally.where(action: action).delete_all,
        samples: RequestSample.where(action: action).delete_all }
    end
  end
end
