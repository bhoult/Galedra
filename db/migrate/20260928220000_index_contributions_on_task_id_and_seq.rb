# frozen_string_literal: true

# A task's results are asked for by task_id on every cold score of a claim
# (Tasks::Checks.accepted_results, Scoring::BuildInputBatch, Sections::Progress,
# Cards::SourceCard), and contributions had no index on task_id: Postgres read
# every TASK_RESULT and filtered, 1,564 rows to find one on galedra.org. That
# one statement was 38% of the node's database time over its first day,
# 21,201 calls at 5.5 ms mean, and it grows with every result recorded
# (pg_stat_statements, 2026-09-28). A plain index rather than a partial one on
# action_type: the statement binds action_type, and a generic plan cannot prove
# a bound value matches a partial index's predicate.
class IndexContributionsOnTaskIdAndSeq < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_index :contributions, [ :task_id, :seq ], algorithm: :concurrently, name: "index_contributions_on_task_id_and_seq"
  end
end
