# Two numbers the weakness lists read, promoted out of the trace and into
# columns of their own.
#
# `claim_scores` carries `trace`, a JSON document averaging about 2 KB, and the
# report read a claim's `independence_unreviewed` and its count of completed
# review checks by rehydrating that whole document — 200,000 of them, 5.0 s of
# SQL in one query shape and most of a 19.6 s Ruby share, to read two integers
# and six fields that were already columns (docs/profiler/2026-09-21-capacity-at-100k-claims.md).
#
# Nothing epistemic lives here: `claim_scores` is a cache outside
# `Ledger::TableDigest`, rebuilt deterministically from the log, so a column may
# be added to it without touching a row or snapshot hash.
class AddListColumnsToClaimScores < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :claim_scores, :independence_unreviewed, :integer
    add_column :claim_scores, :review_checks_done, :integer
    # In batches, and out of the DDL transaction: an unbatched UPDATE over a
    # table of 200,000 rows averaging 2 KB of trace rewrites every tuple while
    # holding ACCESS EXCLUSIVE, which blocks `Watermark.hits` and therefore
    # every scored page on the node for the length of the deploy (code review,
    # 2026-09-22). The readers treat a NULL as nought, so a row this misses is a
    # row that answers honestly rather than raising.
    loop do
      updated = execute(<<~SQL.squish).cmd_tuples
        UPDATE claim_scores SET
        independence_unreviewed = COALESCE((trace->>'independence_unreviewed')::int, 0),
        review_checks_done = COALESCE((
          SELECT count(*) FROM jsonb_each(COALESCE(trace->'review_checklist', '{}'::jsonb)) AS t(k, v)
            WHERE (v->>'ok')::boolean
          ), 0)
        WHERE id IN (SELECT id FROM claim_scores WHERE review_checks_done IS NULL LIMIT 5000)
      SQL
      break if updated.zero?
    end
  end

  def down
    remove_column :claim_scores, :independence_unreviewed
    remove_column :claim_scores, :review_checks_done
  end
end
