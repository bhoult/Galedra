# Missing affiliations (owner request, 2026-09-19): a person asks for one,
# the LLM boundary (stubbed by default) maps it to an existing entry when it
# is a short form or synonym, and admins settle the rest by merging, adding a
# new entry, or declining. Custom entries extend config/affiliations.yml.
class CreateAffiliationRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :custom_affiliations do |t|
      t.string :slug, null: false
      t.string :label, null: false
      t.string :group_slug, null: false
      t.bigint :created_by_id
      t.timestamps
    end
    add_index :custom_affiliations, :slug, unique: true

    create_table :affiliation_requests, id: :uuid, default: nil do |t|
      t.bigint :user_id, null: false
      t.string :text, null: false
      t.string :normalized, null: false
      t.string :proposed_slug
      t.string :confidence
      t.string :status, null: false, default: "PENDING"
      t.string :resolved_slug
      t.bigint :resolved_by_id
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :affiliation_requests, [ :status, :normalized ]
    add_index :affiliation_requests, :user_id
    add_foreign_key :affiliation_requests, :users
  end
end
