# Admin users (implementation/implemented/stage-24-admin-nav.md): the first
# account is an admin; admins grant and revoke admin and moderator on others.
# Who granted it and when is kept so the power stays visible.
class AddAdminToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :admin, :boolean, null: false, default: false
    add_column :users, :admin_granted_by_id, :bigint
    add_column :users, :admin_granted_at, :datetime
    # The first account that already exists is the admin, as a first sign-up would be.
    execute <<~SQL
      UPDATE users SET admin = TRUE, admin_granted_at = NOW()
      WHERE id = (SELECT id FROM users ORDER BY created_at, id LIMIT 1)
    SQL
  end

  def down
    remove_column :users, :admin_granted_at
    remove_column :users, :admin_granted_by_id
    remove_column :users, :admin
  end
end
