# A self-minted token records which address took it, only so that a loop cannot
# take a thousand. Deliberately NOT `source_key`: that column is how
# `Assistants::Connect.for_source` finds the shared anonymous token for an
# address, and putting a self-minted token there would hand the next anonymous
# caller from that address somebody else's credential.
#
# It is the same sha256(address|date) digest the anonymous path already
# computes, so no client IP is stored here either — that stays true.
class AddMintSourceKeyToAssistantTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :assistant_tokens, :mint_source_key, :string
    add_index :assistant_tokens, [ :mint_source_key, :created_at ]
  end
end
