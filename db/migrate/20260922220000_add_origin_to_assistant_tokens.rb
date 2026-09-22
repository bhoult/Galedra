# Where a token came from, said outright rather than inferred.
#
# `self_minted?` first read `mint_source_key`, which exists to bound how many
# tokens one address may take — a rate-limiting detail. Deciding what a token
# may do from a side effect of how we count them is how a privilege ends up
# somewhere nobody intended, so origin is its own field, set once at the mint
# and never changed.
#
#   ADDRESS    keyed by sha256(address|date): everyone behind one address that
#              day, which is not an identity and may not work the queue
#   CONNECTOR  an OAuth grant or an API mint with no person behind it
#   AGENT      the assistant took it through `introduce_yourself`
#   USER       a signed-in person minted it, or a connector completed OAuth
#
# Backfilled from what each existing row already shows. Nothing is guessed: a
# row with a user is USER, a row with a mint source took its own token, a row
# with a source_key is ADDRESS, and what is left came through a flow with
# nobody signed in. None of them gain anything by being named.
class AddOriginToAssistantTokens < ActiveRecord::Migration[8.1]
  def up
    add_column :assistant_tokens, :origin, :string
    execute <<~SQL.squish
      UPDATE assistant_tokens SET origin =
        CASE WHEN user_id IS NOT NULL THEN 'USER'
             WHEN mint_source_key IS NOT NULL THEN 'AGENT'
             WHEN source_key IS NOT NULL THEN 'ADDRESS'
             ELSE 'CONNECTOR' END
    SQL
    change_column_null :assistant_tokens, :origin, false
    add_index :assistant_tokens, :origin
  end

  def down
    remove_column :assistant_tokens, :origin
  end
end
