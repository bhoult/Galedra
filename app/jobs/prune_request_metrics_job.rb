# frozen_string_literal: true

# Stage 40: keeps the request metrics to KEEP_DAYS. Idempotent, and a no-op when
# recording is off and nothing has accumulated.
class PruneRequestMetricsJob < ApplicationJob
  queue_as :default

  def perform(keep_days: RequestMetrics::Prune::DEFAULT_KEEP_DAYS)
    result = RequestMetrics::Prune.call(keep_days: keep_days)
    Rails.logger.info("metrics:prune deleted #{result[:tallies]} tallies and #{result[:samples]} samples")
    result
  end
end
