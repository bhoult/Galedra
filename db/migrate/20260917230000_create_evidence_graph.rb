# The evidence graph projections (spec 02 §3.2–3.3), all written only by
# Ledger::Apply. Every row records the contribution that created it, carries a
# validity window (created_seq / invalidated_seq), and, where the spec says so,
# an accepted_seq. Ids are deterministic (Ledger::Ids) so replay reproduces rows.
# Two small windowed tables make merges and independence-group assignments
# reversible by INVALIDATE without rewriting the rows they affect.
class CreateEvidenceGraph < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"

    create_table :sources, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.string :source_type, null: false
      t.string :title, null: false
      t.string :creator
      t.string :publisher
      t.date :publication_date
      t.string :canonical_uri
      t.jsonb :external_ids, null: false, default: {}
      t.text :content
      t.string :content_hash
      t.timestamptz :retrieved_at
      t.string :license
      t.uuid :previous_version_id
      t.string :lineage_key
      t.jsonb :metadata, null: false, default: {}
      t.bigint :created_seq, null: false
      t.bigint :invalidated_seq
    end
    add_index :sources, :contribution_id
    add_index :sources, :created_seq
    add_index :sources, :invalidated_seq
    add_index :sources, :lineage_key

    create_table :source_locations, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :source_id, null: false
      t.string :locator_type, null: false
      t.jsonb :locator, null: false, default: {}
      t.text :excerpt
      t.string :excerpt_hash
      t.bigint :created_seq, null: false
      t.bigint :invalidated_seq
    end
    add_index :source_locations, :contribution_id
    add_index :source_locations, :source_id
    add_index :source_locations, :created_seq
    add_index :source_locations, :invalidated_seq

    create_table :claims, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.text :canonical_text, null: false
      t.string :claim_type, null: false
      t.boolean :truth_evaluable, null: false
      t.string :not_evaluable_reason
      t.jsonb :qualifiers, null: false, default: {}
      t.string :status, null: false, default: "ACTIVE"
      t.uuid :supersedes_claim_id
      t.uuid :superseded_by_id
      t.uuid :merged_into_id
      t.bigint :created_seq, null: false
      t.bigint :invalidated_seq
      t.bigint :accepted_seq
    end
    add_index :claims, :contribution_id
    add_index :claims, :created_seq
    add_index :claims, :invalidated_seq
    add_index :claims, :accepted_seq
    add_index :claims, :supersedes_claim_id
    add_index :claims, :claim_type
    add_index :claims, "to_tsvector('english', canonical_text)", using: :gin, name: "index_claims_on_canonical_text_fts"
    add_index :claims, :canonical_text, using: :gin, opclass: :gin_trgm_ops, name: "index_claims_on_canonical_text_trgm"

    create_table :claim_edges, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :from_claim_id, null: false
      t.uuid :to_claim_id, null: false
      t.string :relationship_type, null: false
      t.bigint :created_seq, null: false
      t.bigint :invalidated_seq
      t.bigint :accepted_seq
    end
    add_index :claim_edges, :contribution_id
    add_index :claim_edges, :from_claim_id
    add_index :claim_edges, :to_claim_id
    add_index :claim_edges, :created_seq
    add_index :claim_edges, :invalidated_seq

    create_table :independence_groups, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.string :group_type, null: false
      t.text :description
      t.bigint :created_seq, null: false
      t.bigint :invalidated_seq
      t.bigint :accepted_seq
    end
    add_index :independence_groups, :contribution_id
    add_index :independence_groups, :created_seq
    add_index :independence_groups, :invalidated_seq

    create_table :evidence_items, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :source_location_id, null: false
      t.string :observation_type, null: false
      t.text :statement, null: false
      t.jsonb :structured_value
      t.uuid :independence_group_id
      t.jsonb :assessment, null: false, default: {}
      t.bigint :created_seq, null: false
      t.bigint :invalidated_seq
    end
    add_index :evidence_items, :contribution_id
    add_index :evidence_items, :source_location_id
    add_index :evidence_items, :independence_group_id
    add_index :evidence_items, :created_seq
    add_index :evidence_items, :invalidated_seq

    create_table :independence_group_assignments, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :evidence_item_id, null: false
      t.uuid :independence_group_id, null: false
      t.bigint :created_seq, null: false
      t.bigint :invalidated_seq
      t.bigint :accepted_seq
    end
    add_index :independence_group_assignments, :contribution_id
    add_index :independence_group_assignments, :evidence_item_id
    add_index :independence_group_assignments, :created_seq
    add_index :independence_group_assignments, :invalidated_seq

    create_table :evidence_claim_links, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :evidence_item_id, null: false
      t.uuid :claim_id, null: false
      t.string :direction, null: false
      t.string :relevance_strength, null: false
      t.integer :interpretive_steps, null: false, default: 0
      t.text :note
      t.uuid :supersedes_link_id
      t.bigint :created_seq, null: false
      t.bigint :invalidated_seq
      t.bigint :accepted_seq
    end
    add_index :evidence_claim_links, :contribution_id
    add_index :evidence_claim_links, [ :claim_id, :created_seq ]
    add_index :evidence_claim_links, :evidence_item_id
    add_index :evidence_claim_links, :supersedes_link_id
    add_index :evidence_claim_links, :created_seq
    add_index :evidence_claim_links, :invalidated_seq

    create_table :claim_merges, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :from_claim_id, null: false
      t.uuid :into_claim_id, null: false
      t.bigint :created_seq, null: false
      t.bigint :invalidated_seq
      t.bigint :accepted_seq
    end
    add_index :claim_merges, :contribution_id
    add_index :claim_merges, :from_claim_id
    add_index :claim_merges, :into_claim_id

    create_table :claim_evaluability_settings, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :claim_id, null: false
      t.boolean :truth_evaluable, null: false
      t.string :not_evaluable_reason
      t.bigint :created_seq, null: false
      t.bigint :invalidated_seq
      t.bigint :accepted_seq
    end
    add_index :claim_evaluability_settings, :contribution_id
    add_index :claim_evaluability_settings, :claim_id

    add_foreign_key :source_locations, :sources
    add_foreign_key :claims, :claims, column: :supersedes_claim_id
    add_foreign_key :claim_edges, :claims, column: :from_claim_id
    add_foreign_key :claim_edges, :claims, column: :to_claim_id
    add_foreign_key :evidence_items, :source_locations
    add_foreign_key :evidence_items, :independence_groups
    add_foreign_key :independence_group_assignments, :evidence_items
    add_foreign_key :independence_group_assignments, :independence_groups
    add_foreign_key :evidence_claim_links, :evidence_items
    add_foreign_key :evidence_claim_links, :claims
    add_foreign_key :evidence_claim_links, :evidence_claim_links, column: :supersedes_link_id
    add_foreign_key :claim_merges, :claims, column: :from_claim_id
    add_foreign_key :claim_merges, :claims, column: :into_claim_id
    add_foreign_key :claim_evaluability_settings, :claims
  end
end
