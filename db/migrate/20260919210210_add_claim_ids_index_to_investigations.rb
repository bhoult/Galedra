# The claim page asks which recorded checks a claim appeared in, which means
# searching an array column. GIN is the index for containment.
class AddClaimIdsIndexToInvestigations < ActiveRecord::Migration[8.1]
  def change
    add_index :investigations, :claim_ids, using: :gin
  end
end
