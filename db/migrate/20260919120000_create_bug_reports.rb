# Bug reports from assistants and people (owner request, 2026-09-19), the
# sibling of feature_requests: untrusted text outside the log, read by admins
# and moderators only. Repeats within a month are counted, not duplicated.
class CreateBugReports < ActiveRecord::Migration[8.1]
  def change
    create_table :bug_reports, id: :uuid, default: nil do |t|
      t.uuid :assistant_token_id
      t.bigint :user_id
      t.text :happened, null: false
      t.text :expected
      t.text :steps
      t.string :url
      t.string :context_tool
      t.string :last_error
      t.boolean :anonymous, null: false, default: false
      t.string :digest, null: false
      t.integer :count, null: false, default: 1
      t.timestamps
    end
    add_index :bug_reports, :digest
    add_index :bug_reports, :created_at
    add_foreign_key :bug_reports, :assistant_tokens
    add_foreign_key :bug_reports, :users
  end
end
