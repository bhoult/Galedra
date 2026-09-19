# Stage 25: a recorded reasoning step: "because these claims hold and that one
# does not, this follows." Interpretation, never evidence (Article III): it
# carries no weight in any released model. Projection of CREATE_INFERENCE.
class CreateInferences < ActiveRecord::Migration[8.1]
  def change
    create_table :inferences, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :conclusion_claim_id, null: false
      t.string :inference_type, null: false
      t.string :rule
      t.string :strength, null: false
      t.bigint :created_seq, null: false
      t.bigint :accepted_seq
      t.bigint :invalidated_seq
      t.bigint :redacted_by_seq
    end
    add_index :inferences, :conclusion_claim_id
    add_index :inferences, :contribution_id

    create_table :inference_premises, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :inference_id, null: false
      t.uuid :claim_id, null: false
      t.string :polarity, null: false
      t.integer :position, null: false, default: 0
      t.bigint :created_seq, null: false
      t.bigint :accepted_seq
      t.bigint :invalidated_seq
    end
    add_index :inference_premises, [ :inference_id, :position ]
    add_index :inference_premises, :claim_id
  end
end
