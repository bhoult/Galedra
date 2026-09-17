# Spec 02 §3.1. UUIDv7 ids are assigned in Ruby (ApplicationRecord), so the
# column has no database default.
class CreateContributors < ActiveRecord::Migration[8.1]
  def change
    create_table :contributors, id: :uuid, default: nil do |t|
      t.string :key_id, null: false
      t.string :public_key, null: false
      t.string :kind, null: false
      t.string :display_name
      t.string :identity_tier, null: false, default: "PSEUDONYMOUS"
      t.text :encrypted_private_key
      t.references :user, foreign_key: true
      t.bigint :created_seq
      t.bigint :revoked_seq
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :contributors, :key_id, unique: true
  end
end
