# How often a claim is referenced (owner request, 2026-09-19): checked in an
# investigation, looked up by an assistant, viewed, or shared. One row per
# claim, kind, and day; outside the log (a count, not an epistemic fact).
class CreateClaimReferences < ActiveRecord::Migration[8.1]
  def change
    create_table :claim_references, id: :uuid, default: nil do |t|
      t.uuid :claim_id, null: false
      t.string :kind, null: false
      t.date :day, null: false
      t.integer :count, null: false, default: 0
    end
    add_index :claim_references, [ :claim_id, :kind, :day ], unique: true
    add_index :claim_references, [ :kind, :day ]
    # No foreign key: replay truncates the projection tables and rebuilds them
    # with the same derived ids, and the counts must survive that.
  end
end
