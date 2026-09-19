# Consensus review (owner request, 2026-09-19): reviews are settled by the
# agreement of different principals, never by the author's own and never by a
# paid admin. One verdict per principal per item; the author is excluded.
class CreateReviewVerdicts < ActiveRecord::Migration[8.1]
  def change
    create_table :review_verdicts, id: :uuid, default: nil do |t|
      t.string :subject_type, null: false
      t.string :subject_key, null: false
      t.uuid :principal_contributor_id, null: false
      t.uuid :assistant_token_id
      t.string :verdict, null: false
      t.jsonb :detail, null: false, default: {}
      t.string :reason
      t.datetime :created_at, null: false
    end
    add_index :review_verdicts, [ :subject_type, :subject_key, :principal_contributor_id ], unique: true, name: "index_review_verdicts_one_per_principal"
    add_column :content_reviews, :author_principal_id, :uuid
  end
end
