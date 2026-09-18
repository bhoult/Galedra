# Summary cache (spec 02 §3.5): derived, never evidence, keyed by the hash of
# its deterministic input so a changed graph never serves a stale summary.
class CreateSummaries < ActiveRecord::Migration[8.1]
  def change
    create_table :summaries, id: :uuid, default: nil do |t|
      t.uuid :claim_id, null: false
      t.bigint :snapshot_seq, null: false
      t.uuid :scoring_model_id, null: false
      t.string :summary_type, null: false
      t.string :input_hash, null: false
      t.string :generator, null: false
      t.jsonb :sentences, null: false
      t.timestamptz :created_at, null: false
    end
    add_index :summaries, [ :claim_id, :snapshot_seq, :scoring_model_id, :summary_type ], unique: true, name: "index_summaries_on_claim_seq_model_type"
  end
end
