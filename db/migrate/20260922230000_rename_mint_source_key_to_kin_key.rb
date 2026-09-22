# `mint_source_key` was named for the only thing it did when it was added: bound
# how many tokens one address may take in a day. It now decides something more
# consequential — which principals count as one for independence — so it is
# named for that instead. A column whose name describes its first use is a
# column the next reader will misjudge.
#
# Kin means "took its token from the same place": one address, or one OAuth
# client. A task wants three independent answers from three principals, and
# without this a single actor holding several tokens is three of them
# (Article XII, resist capture).
#
# Backfilled for OAuth-granted tokens, which carry their client in `software`
# and were identifiable all along without anybody asking.
class RenameMintSourceKeyToKinKey < ActiveRecord::Migration[8.1]
  def up
    rename_column :assistant_tokens, :mint_source_key, :kin_key
    execute <<~SQL.squish
      UPDATE assistant_tokens
         SET kin_key = 'oauth:' || (software->>'oauth_client_id')
       WHERE kin_key IS NULL AND software->>'oauth_client_id' IS NOT NULL
    SQL
  end

  def down
    rename_column :assistant_tokens, :kin_key, :mint_source_key
  end
end
