# Released scoring models (spec 02 §3.5). A projection of RELEASE_SCORING_MODEL
# contributions, so it carries released_seq rather than a wall-clock created_at.
class CreateScoringModels < ActiveRecord::Migration[8.1]
  def change
    create_table :scoring_models, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.string :name, null: false
      t.string :semantic_version, null: false
      t.jsonb :config, null: false
      t.string :config_hash, null: false
      t.string :code_hash, null: false
      t.string :test_suite_result_hash
      t.string :release_signature, null: false
      t.bigint :released_seq, null: false
    end
    add_index :scoring_models, [ :name, :semantic_version ], unique: true
    add_index :scoring_models, :contribution_id
  end
end
