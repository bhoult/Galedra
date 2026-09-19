# Stage 17: what Galedra's own trusted job found when it fetched a source held
# by reference. A projection of RETRIEVE_SOURCE (system-signed): the outcome,
# the server's hash and size of what it received, and whether each quoted
# excerpt was found. Page text is never stored.
class CreateSourceRetrievals < ActiveRecord::Migration[8.1]
  def change
    create_table :source_retrievals, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :source_id, null: false
      t.bigint :source_created_seq, null: false
      t.string :outcome, null: false
      t.timestamptz :fetched_at, null: false
      t.string :content_hash
      t.integer :content_length
      t.string :media_type
      t.string :final_url
      t.jsonb :excerpts, null: false, default: []
      t.bigint :created_seq, null: false
      t.bigint :invalidated_seq
      t.bigint :redacted_by_seq
    end
    add_index :source_retrievals, [ :source_id, :created_seq ]
    add_index :source_retrievals, :contribution_id
  end
end
