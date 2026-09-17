# Spec 02 §3.1. A projection written only by Ledger::Apply (DELEGATE).
class CreateAgentDelegations < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_delegations, id: :uuid, default: nil do |t|
      t.uuid :principal_contributor_id, null: false
      t.uuid :delegate_contributor_id, null: false
      t.jsonb :permissions, null: false, default: {}
      t.integer :max_tasks_per_day
      t.timestamptz :valid_from, null: false
      t.timestamptz :valid_until, null: false
      t.string :delegation_signature, null: false
      t.bigint :created_seq, null: false
      t.bigint :revoked_seq
    end

    add_index :agent_delegations, :delegate_contributor_id
    add_index :agent_delegations, :principal_contributor_id
  end
end
