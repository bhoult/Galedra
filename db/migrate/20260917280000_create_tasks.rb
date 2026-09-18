# Tasks and leases (spec 02 §3.4, 04 §7). Operational tables, not projections:
# task creation is not a log action, results are. Sources created by agents
# inside a task are metadata-only until content is imported (04 §6 step 9).
class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks, id: :uuid, default: nil do |t|
      t.string :task_type, null: false
      t.string :target_type, null: false
      t.uuid :target_id, null: false
      t.string :domain, null: false
      t.decimal :priority, precision: 10, scale: 4, null: false, default: 0
      t.integer :required_assignments, null: false, default: 1
      t.string :status, null: false, default: "OPEN"
      t.jsonb :packet, null: false
      t.string :packet_hash, null: false
      t.bigint :issued_seq, null: false
      t.uuid :created_by_contributor_id
      t.timestamps
    end
    add_index :tasks, [ :status, :priority ], order: { priority: :desc }
    add_index :tasks, [ :target_type, :target_id ]
    add_index :tasks, :task_type
    add_index :tasks, :packet_hash, unique: true

    create_table :task_assignments, id: :uuid, default: nil do |t|
      t.uuid :task_id, null: false
      t.uuid :contributor_id, null: false
      t.uuid :principal_contributor_id, null: false
      t.uuid :delegation_id
      t.timestamptz :lease_expires_at, null: false
      t.uuid :result_contribution_id
      t.string :status, null: false, default: "LEASED"
      t.timestamps
    end
    add_index :task_assignments, [ :task_id, :contributor_id ], unique: true
    add_index :task_assignments, [ :task_id, :principal_contributor_id ], unique: true
    add_index :task_assignments, [ :contributor_id, :created_at ]
    add_index :task_assignments, [ :status, :lease_expires_at ]
    add_foreign_key :task_assignments, :tasks

    add_column :sources, :retrieval_pending, :boolean, null: false, default: false
  end
end
