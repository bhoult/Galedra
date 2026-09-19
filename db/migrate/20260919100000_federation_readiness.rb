# Federation readiness (implementation/implemented/stage-23-federation-ready.md,
# spec 14 §5, §7, §10, §25): a key names the node it lives on, every log entry
# carries an explicit visibility, and a pinned snapshot carries a signed
# checkpoint. Nothing here changes what is signed by clients.
class FederationReadiness < ActiveRecord::Migration[8.1]
  def change
    add_column :contributors, :home_url, :string
    add_column :contributions, :visibility, :string, null: false, default: "PUBLIC"
    add_column :graph_snapshots, :checkpoint, :jsonb
  end
end
