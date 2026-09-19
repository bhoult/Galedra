# frozen_string_literal: true

module Scoring
  # Retention for the score cache (Stage 26).
  #
  # `claim_scores` is keyed (claim_id, snapshot_seq, scoring_model_id), so every
  # claim scored at every distinct seq under every model leaves a row carrying
  # its whole trace, and nothing ever removed one. At 3,026 claims the cache was
  # 18 MB against 70 MB of log, growing faster than the thing it caches.
  #
  # Deleting a row loses nothing epistemic. A score is a pure function of the
  # log up to a seq and a versioned model (Invariant 4), so a pruned row comes
  # back byte-identical on the next read. That property is what makes a cache
  # safe to discard, and it is the only reason this is allowed to delete
  # anything at all.
  #
  # Kept: the head seq, because that is what pages ask for; every pinned
  # snapshot, because those are citable and meant to stay reproducible cheaply;
  # and anything computed recently, so a node under load does not throw away
  # work it is about to want again.
  module Prune
    DEFAULT_KEEP_DAYS = 7
    BATCH = 5_000

    Result = Struct.new(:deleted, :kept, :seqs_kept, :bytes_before, :bytes_after, keyword_init: true)

    module_function

    def call(keep_days: DEFAULT_KEEP_DAYS, dry_run: false, out: nil)
      before = size
      kept_seqs = protected_seqs
      scope = ClaimScore.where.not(snapshot_seq: kept_seqs)
      scope = scope.where(computed_at: ...keep_days.days.ago) if keep_days&.positive?

      deleted = dry_run ? scope.count : delete_in_batches(scope)
      result = Result.new(deleted: deleted, kept: ClaimScore.count, seqs_kept: kept_seqs.size,
                          bytes_before: before, bytes_after: size)
      report(result, keep_days, dry_run, out) if out
      result
    end

    # The head, and every seq a snapshot was pinned at. Both are sets a reader
    # can ask for by name, so their scores stay cheap to serve.
    def protected_seqs
      ([ Contribution.maximum(:seq) ] + GraphSnapshot.pluck(:seq)).compact.uniq
    end

    # In batches, so a long-neglected cache does not become one statement that
    # locks the table for the length of a request.
    def delete_in_batches(scope)
      total = 0
      loop do
        ids = scope.limit(BATCH).pluck(:id)
        break if ids.empty?

        total += ClaimScore.where(id: ids).delete_all
      end
      total
    end

    def size
      ActiveRecord::Base.connection.select_value("SELECT pg_total_relation_size('claim_scores')").to_i
    end

    def report(result, keep_days, dry_run, out)
      out.puts "#{dry_run ? 'would delete' : 'deleted'} #{result.deleted} rows; #{result.kept} remain"
      out.puts "kept the head seq, #{result.seqs_kept - 1} pinned snapshot(s), and anything scored in the last #{keep_days} days"
      out.puts "claim_scores #{human(result.bytes_before)} -> #{human(result.bytes_after)}" unless dry_run
      out.puts "every pruned row recomputes byte-identically from the log; nothing epistemic was lost"
    end

    def human(bytes)
      return "#{bytes} B" if bytes < 1024
      return format("%.1f KB", bytes / 1024.0) if bytes < 1024 * 1024

      format("%.1f MB", bytes / 1024.0 / 1024)
    end
  end
end
