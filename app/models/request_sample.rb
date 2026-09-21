# Stage 40: one request that took longer than RequestMetrics::SLOW_MS, or issued
# more than RequestMetrics::MANY_STATEMENTS statements.
#
# The statement count is the point. The Rails log records duration and not the
# number of queries, and every slow path found on 2026-09-21 was found by
# counting statements rather than by reading a duration.
class RequestSample < ApplicationRecord
  scope :slowest, -> { order(duration_ms: :desc) }
  scope :recent, -> { order(recorded_at: :desc) }
end
