# Claims created from a pasted text in the UI record the source they were
# extracted from, so the per-source answer card can list them alongside claims
# proposed by CLAIM_EXTRACTION tasks (spec 06 §5).
class AddExtractedFromSourceToClaims < ActiveRecord::Migration[8.1]
  def change
    add_column :claims, :extracted_from_source_id, :uuid
    add_index :claims, :extracted_from_source_id
  end
end
