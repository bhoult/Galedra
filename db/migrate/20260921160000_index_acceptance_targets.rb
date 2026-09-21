# Stage 39, finding 1: the query that asks "was this entry accepted, and not
# invalidated, as of a seq" had no index to use.
#
# `Contributions::Standing` filters on `payload->>'contribution_id'`, which
# nothing covered, so Postgres walked the `seq` index backwards and threw away
# every row that did not match. That is linear in the length of the log, per
# call, and `/sections/:id` makes 780 calls.
#
# Measured on the dev node at 5,165 contributions, before:
#
#   Index Scan Backward using index_contributions_on_seq
#     Filter: action_type = 'ACCEPT' AND payload->>'contribution_id' = $1
#     Rows Removed by Filter: 5001
#     Buffers: shared hit=3543 read=1454
#     Execution Time: 73.721 ms
#
# At 900,001 contributions the same call was measured at 6,853 ms. After:
#
#   Index Scan Backward using index_contributions_on_acceptance_target
#     Index Cond: payload->>'contribution_id' = $1 AND seq <= $2
#     Buffers: shared hit=3 read=2
#     Execution Time: 0.026 ms
#
# A filter over five thousand rows became a lookup: 73.7 ms to 0.026 ms, and
# 4,997 buffers to 5. The index is partial — ACCEPT and INVALIDATE are the only
# action types whose payload carries `contribution_id` for this purpose — so it
# stays small, and it carries `seq` so the MAX is answered from the index.
class IndexAcceptanceTargets < ActiveRecord::Migration[8.1]
  def change
    add_index :contributions, "(payload->>'contribution_id'), seq",
              where: "action_type IN ('ACCEPT', 'INVALIDATE')",
              name: "index_contributions_on_acceptance_target"
  end
end
