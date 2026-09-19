# frozen_string_literal: true

namespace :scores do
  desc "Trim the score cache: bin/rails scores:prune (KEEP_DAYS=7, DRY_RUN=1 to count only)"
  task prune: :environment do
    Scoring::Prune.call(keep_days: Integer(ENV.fetch("KEEP_DAYS", Scoring::Prune::DEFAULT_KEEP_DAYS)),
                        dry_run: ENV["DRY_RUN"] == "1", out: $stdout)
  end
end
