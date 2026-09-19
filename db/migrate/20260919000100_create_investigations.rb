# A shareable record of one check (after Stage 19): what was asked, and which
# claims answer it. An index over log content, like receipts; the claims and
# their cards are read live from the log.
class CreateInvestigations < ActiveRecord::Migration[8.1]
  def change
    create_table :investigations, id: :uuid, default: nil do |t|
      t.uuid :assistant_token_id, null: false
      t.text :statement
      t.uuid :claim_ids, array: true, null: false, default: []
      t.integer :snapshot_seq, null: false
      t.timestamps
    end
    add_index :investigations, :created_at
    add_foreign_key :investigations, :assistant_tokens
  end
end
