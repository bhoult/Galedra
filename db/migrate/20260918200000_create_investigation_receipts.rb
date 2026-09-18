class CreateInvestigationReceipts < ActiveRecord::Migration[8.1]
  def change
    # Idempotency for recorded investigations: the same token and the same
    # bundle record once. Operational, like assistant_tokens; the log holds
    # the contributions themselves.
    create_table :investigation_receipts, id: :uuid, default: nil do |t|
      t.uuid :assistant_token_id, null: false
      t.string :bundle_digest, null: false
      t.jsonb :result, null: false, default: {}
      t.timestamps
    end
    add_index :investigation_receipts, [ :assistant_token_id, :bundle_digest ], unique: true
  end
end
