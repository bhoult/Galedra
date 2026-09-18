class AddAdoptionToAssistantTokens < ActiveRecord::Migration[8.1]
  def change
    # Anonymous work can be put under an account later. Each anonymous
    # assistant carries an adoption code: the code itself is stored encrypted
    # so it can be shown in every response, and its digest is indexed for lookup.
    add_column :assistant_tokens, :adoption_code, :text
    add_column :assistant_tokens, :adoption_digest, :string
    add_index :assistant_tokens, :adoption_digest, unique: true
  end
end
