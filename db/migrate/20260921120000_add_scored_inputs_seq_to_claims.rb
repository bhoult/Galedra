# Stage 38: the high-water mark of everything that can change a claim's score,
# so the cache stops being invalidated by writes that have nothing to do with it.
#
# The backfill sets every existing claim to the current head, which is what the
# old key meant anyway: nothing is treated as unchanged until a stamp says so.
# A mark derived from the projections instead would have to enumerate the
# dependency set to backfill, and a mistake there would serve a stale score with
# no write to correct it. Head costs one recomputation per claim and cannot lie.
class AddScoredInputsSeqToClaims < ActiveRecord::Migration[8.1]
  def up
    add_column :claims, :scored_inputs_seq, :bigint
    execute <<~SQL.squish
      UPDATE claims SET scored_inputs_seq = COALESCE((SELECT MAX(seq) FROM contributions), created_seq)
    SQL
    add_index :claims, :scored_inputs_seq
  end

  def down
    remove_column :claims, :scored_inputs_seq
  end
end
