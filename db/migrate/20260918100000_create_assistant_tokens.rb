class CreateAssistantTokens < ActiveRecord::Migration[8.1]
  def change
    # Anonymous principals have a server-custodied key and no account.
    change_column_null :custodied_keys, :user_id, true

    # Not a projection: like custodied_keys, tokens survive replay. The
    # delegation they point at is the log's record of the grant.
    create_table :assistant_tokens, id: :uuid, default: nil do |t|
      t.string :token_digest, null: false
      t.uuid :agent_contributor_id, null: false
      t.uuid :principal_contributor_id, null: false
      t.uuid :delegation_id, null: false
      t.bigint :user_id
      t.jsonb :software, null: false, default: {}
      t.integer :daily_cap, null: false, default: 200
      t.timestamptz :last_used_at
      t.timestamptz :revoked_at
      t.timestamps
    end
    add_index :assistant_tokens, :token_digest, unique: true
    add_index :assistant_tokens, :agent_contributor_id, unique: true
    add_index :assistant_tokens, :user_id
  end
end
