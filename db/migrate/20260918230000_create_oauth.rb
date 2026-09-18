class CreateOauth < ActiveRecord::Migration[8.1]
  def change
    # OAuth 2.1 for connectors (Stage 16). Operational tables, like
    # assistant_tokens: the durable fact, the delegation, is in the log.
    create_table :oauth_clients, id: :uuid, default: nil do |t|
      t.string :client_id, null: false
      t.string :client_secret_digest
      t.string :name, null: false
      t.string :redirect_uris, array: true, null: false, default: []
      t.string :token_endpoint_auth_method, null: false, default: "none"
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :oauth_clients, :client_id, unique: true

    create_table :oauth_authorization_codes, id: :uuid, default: nil do |t|
      t.string :code_digest, null: false
      t.references :oauth_client, type: :uuid, null: false, foreign_key: true
      t.bigint :user_id, null: false
      t.string :redirect_uri, null: false
      t.string :code_challenge, null: false
      t.string :scope
      t.string :resource
      t.timestamptz :expires_at, null: false
      t.timestamptz :used_at
      t.timestamps
    end
    add_index :oauth_authorization_codes, :code_digest, unique: true

    create_table :oauth_tokens, id: :uuid, default: nil do |t|
      t.string :token_digest, null: false
      t.string :kind, null: false
      t.uuid :family_id, null: false
      t.references :oauth_client, type: :uuid, null: false, foreign_key: true
      t.references :assistant_token, type: :uuid, null: false, foreign_key: true
      t.string :scope
      t.timestamptz :expires_at, null: false
      t.timestamptz :revoked_at
      t.timestamptz :used_at
      t.timestamps
    end
    add_index :oauth_tokens, :token_digest, unique: true
    add_index :oauth_tokens, :family_id
  end
end
