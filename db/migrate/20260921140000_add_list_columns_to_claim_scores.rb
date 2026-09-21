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
  def up
    add_column :claim_scores, :independence_unreviewed, :integer
    add_column :claim_scores, :review_checks_done, :integer
    execute <<~SQL.squish
      UPDATE claim_scores SET
        independence_unreviewed = COALESCE((trace->>'independence_unreviewed')::int, 0),
        review_checks_done = COALESCE((
          SELECT count(*) FROM jsonb_each(COALESCE(trace->'review_checklist', '{}'::jsonb)) AS t(k, v)
          WHERE (v->>'ok')::boolean
        ), 0)
    SQL
  end

  def down
    remove_column :claim_scores, :independence_unreviewed
    remove_column :claim_scores, :review_checks_done
  end
end
