# What an assistant wanted to do and could not (owner request, after Stage 19).
# Not ledger content: untrusted text read only by moderators.
class CreateFeatureRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :feature_requests, id: :uuid, default: nil do |t|
      t.uuid :assistant_token_id, null: false
      t.text :asked, null: false
      t.text :needed, null: false
      t.string :expected
      t.string :context_tool
      t.string :last_error
      t.boolean :anonymous, null: false, default: false
      t.string :digest, null: false
      t.integer :count, null: false, default: 1
      t.timestamps
    end
    add_index :feature_requests, :digest
    add_index :feature_requests, :created_at
    add_foreign_key :feature_requests, :assistant_tokens
  end
end
