# Contributors are a projection: ledger:replay truncates and rebuilds them from
# the log, so they cannot hold server-custodied private keys or user links
# (which are not in the log). Those move to custodied_keys, an operational table
# outside the projection set. Projection rows also drop wall-clock timestamps so
# replay reproduces them byte for byte; created_seq is the time axis.
class MoveCustodyToCustodiedKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :custodied_keys, id: :uuid, default: nil do |t|
      t.uuid :contributor_id, null: false
      t.references :user, null: false, foreign_key: true
      t.text :encrypted_private_key, null: false

      t.timestamps
    end
    add_index :custodied_keys, :contributor_id, unique: true

    remove_reference :contributors, :user, foreign_key: true
    remove_column :contributors, :encrypted_private_key, :text
    remove_column :contributors, :created_at, :datetime, null: false
    remove_column :contributors, :updated_at, :datetime, null: false
  end
end
