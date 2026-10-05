class CreatePreliminaryResults < ActiveRecord::Migration[8.1]
  def change
    # Projection of CREATE_PRELIMINARY_RESULT (Stage 45): an assistant's first
    # reading of one claim, recorded before any source is read into Galedra.
    # Windowed like every projection; never read by scoring or by a packet.
    create_table :preliminary_results, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :claim_id, null: false
      t.string :expectation, null: false
      t.text :rationale
      t.jsonb :leads, null: false, default: []
      t.string :model
      t.uuid :principal_contributor_id
      t.bigint :created_seq, null: false
      t.bigint :accepted_seq
      t.bigint :invalidated_seq
      t.bigint :redacted_by_seq
    end
    add_index :preliminary_results, :claim_id
    add_index :preliminary_results, :contribution_id

    # Which preliminaries belong to which check. A claim can sit in several
    # checks through attach_to, each with its own first reading, and a check
    # lives outside the log, so it points into the log the way claim_ids does.
    add_column :investigations, :preliminary_contribution_ids, :uuid, array: true, default: [], null: false
  end
end
