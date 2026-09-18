class CreateClaimTopics < ActiveRecord::Migration[8.1]
  def change
    # Projection of TAG_CLAIM (Stage 15): one row per topic per tag, windowed
    # like every projection, and replaced when the same principal tags the
    # claim again.
    create_table :claim_topics, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :claim_id, null: false
      t.string :topic, null: false
      t.uuid :principal_contributor_id
      t.string :note
      t.bigint :created_seq, null: false
      t.bigint :accepted_seq
      t.bigint :invalidated_seq
      t.bigint :replaced_seq
    end
    add_index :claim_topics, [ :claim_id, :topic ]
    add_index :claim_topics, :topic
    add_index :claim_topics, :contribution_id
  end
end
