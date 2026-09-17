# Score cache and pinned snapshots (spec 02 §3.5). claim_scores is a cache:
# delete it freely, every row is recomputable. graph_snapshots pins a
# (seq, entry_hash); the chain head commits to the whole prefix, so no Merkle tree.
class CreateScoresAndSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :claim_scores, id: :uuid, default: nil do |t|
      t.uuid :claim_id, null: false
      t.bigint :snapshot_seq, null: false
      t.uuid :scoring_model_id, null: false
      t.string :assessment_state, null: false
      t.decimal :probability, precision: 5, scale: 4
      t.decimal :review_coverage, precision: 3, scale: 2, null: false
      t.string :stability
      t.integer :support_groups, null: false
      t.integer :contradict_groups, null: false
      t.boolean :contested, null: false
      t.boolean :provisional, null: false
      t.jsonb :trace, null: false
      t.string :trace_hash, null: false
      t.timestamptz :computed_at, null: false
    end
    add_index :claim_scores, [ :claim_id, :snapshot_seq, :scoring_model_id ], unique: true
    add_index :claim_scores, [ :snapshot_seq, :scoring_model_id ]

    create_table :graph_snapshots, id: :uuid, default: nil do |t|
      t.bigint :seq, null: false
      t.string :entry_hash, null: false
      t.string :label
      t.timestamptz :created_at, null: false
    end
    add_index :graph_snapshots, :seq, unique: true
  end
end
