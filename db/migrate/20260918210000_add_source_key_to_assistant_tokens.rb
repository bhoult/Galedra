class AddSourceKeyToAssistantTokens < ActiveRecord::Migration[8.1]
  def change
    # Anonymous writes with no token: one assistant per calling source per
    # day, keyed by a digest of the address, minted on first use.
    add_column :assistant_tokens, :source_key, :string
    add_index :assistant_tokens, :source_key, unique: true
  end
end
