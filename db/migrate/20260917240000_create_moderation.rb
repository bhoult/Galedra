# Visible moderation (spec 05 §13, 02 §5): quarantines as a windowed projection,
# redaction markers on every projection row, and nullable text columns so a
# TAKEDOWN can remove bytes while the row and its hashes remain.
class CreateModeration < ActiveRecord::Migration[8.1]
  PROJECTIONS = %i[sources source_locations claims claim_edges independence_groups evidence_items
                   independence_group_assignments evidence_claim_links claim_merges claim_evaluability_settings].freeze

  def change
    create_table :quarantines, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.string :target_type, null: false
      t.uuid :target_id, null: false
      t.string :reason, null: false
      t.text :note
      t.bigint :created_seq, null: false
      t.bigint :released_seq
      t.uuid :release_contribution_id
    end
    add_index :quarantines, [ :target_type, :target_id ]
    add_index :quarantines, :contribution_id
    add_index :quarantines, :released_seq

    PROJECTIONS.each { |table| add_column table, :redacted_by_seq, :bigint }

    change_column_null :sources, :title, true
    change_column_null :claims, :canonical_text, true
    change_column_null :evidence_items, :statement, true

    add_column :users, :moderator, :boolean, null: false, default: false
  end
end
