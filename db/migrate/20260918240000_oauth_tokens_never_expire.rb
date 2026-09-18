class OauthTokensNeverExpire < ActiveRecord::Migration[8.1]
  def change
    # Owner decision (Stage 16): OAuth tokens do not expire; revocation is the
    # only way they end. expires_at stays for the record but may be null.
    change_column_null :oauth_tokens, :expires_at, true
  end
end
