# frozen_string_literal: true

# Trims the score cache (Stage 26). Idempotent: running it twice deletes
# nothing the second time, and a row it deleted is recomputed on the next read.
class PruneClaimScoresJob < ApplicationJob
  queue_as :default

  def perform(keep_days: Scoring::Prune::DEFAULT_KEEP_DAYS)
    result = Scoring::Prune.call(keep_days: keep_days)
    Rails.logger.info("scores:prune deleted #{result.deleted} rows, #{result.kept} remain")
    result
  end
end
