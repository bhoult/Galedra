# Content review (owner request, 2026-09-19): every piece of free text a
# person or assistant adds outside the log is queued for review; a reviewer
# (an assistant working the queue, or an admin) marks it clean or redacts it.
# The original text is kept on the review row so an admin can restore it.
class CreateContentReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :content_reviews, id: :uuid, default: nil do |t|
      t.string :subject_type, null: false
      t.uuid :subject_id
      t.bigint :subject_int_id
      t.string :field, null: false
      t.text :original_text, null: false
      t.string :status, null: false, default: "PENDING"
      t.uuid :leased_by_token_id
      t.datetime :lease_expires_at
      t.uuid :reviewed_by_token_id
      t.bigint :reviewed_by_user_id
      t.string :reason
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :content_reviews, [ :status, :created_at ]
    add_index :content_reviews, [ :subject_type, :subject_id, :field ]
  end
end
