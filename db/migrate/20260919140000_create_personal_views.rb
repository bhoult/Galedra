# Personal views (owner request, 2026-09-19): the personal assessments layer
# spec 02 §3.6a reserved, plus self-declared affiliations. Outside the log
# (Article XV): never fed to Ledger::Apply, scoring, packets, or summaries.
# No foreign key to claims, so replay's truncate leaves these standing.
class CreatePersonalViews < ActiveRecord::Migration[8.1]
  def change
    create_table :user_affiliations do |t|
      t.bigint :user_id, null: false
      t.string :affiliation, null: false
      t.datetime :created_at, null: false
    end
    add_index :user_affiliations, [ :user_id, :affiliation ], unique: true
    add_index :user_affiliations, :affiliation
    add_foreign_key :user_affiliations, :users

    create_table :personal_assessments, id: :uuid, default: nil do |t|
      t.bigint :user_id, null: false
      t.uuid :claim_id, null: false
      t.string :stance, null: false
      t.text :rationale
      t.jsonb :lens, null: false, default: {}
      t.string :personal_probability
      t.jsonb :cites, null: false, default: []
      t.string :visibility, null: false, default: "PRIVATE"
      t.timestamps
    end
    add_index :personal_assessments, [ :user_id, :claim_id ], unique: true
    add_index :personal_assessments, [ :claim_id, :stance ]
    add_foreign_key :personal_assessments, :users
  end
end
