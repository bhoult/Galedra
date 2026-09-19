# Stage 20: outlines. A section is a node of a tree over one source; a claim
# is placed in a section by a placement. Both are projections of signed
# contributions (CREATE_SECTION, PLACE_CLAIM, or CREATE_CLAIM with section_id),
# windowed like every projection, replayed from the log.
class CreateSections < ActiveRecord::Migration[8.1]
  def change
    create_table :sections, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :source_id, null: false
      t.uuid :root_id, null: false
      t.uuid :parent_id
      t.integer :depth, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.string :heading, null: false
      t.uuid :location_id
      t.bigint :created_seq, null: false
      t.bigint :accepted_seq
      t.bigint :invalidated_seq
      t.bigint :redacted_by_seq
    end
    add_index :sections, [ :root_id, :parent_id, :position ]
    add_index :sections, :source_id
    add_index :sections, :contribution_id

    create_table :claim_placements, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :claim_id, null: false
      t.uuid :section_id, null: false
      t.integer :position, null: false, default: 0
      t.bigint :created_seq, null: false
      t.bigint :accepted_seq
      t.bigint :invalidated_seq
    end
    add_index :claim_placements, [ :section_id, :position ]
    add_index :claim_placements, :claim_id
    add_index :claim_placements, :contribution_id
  end
end
