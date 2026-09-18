class AnonymousOauthGrants < ActiveRecord::Migration[8.1]
  def change
    # Owner decision: the person chooses on the consent page whether to sign
    # in or continue anonymously, so a code may carry no user.
    change_column_null :oauth_authorization_codes, :user_id, true
    add_column :oauth_authorization_codes, :anonymous, :boolean, null: false, default: false
  end
end
