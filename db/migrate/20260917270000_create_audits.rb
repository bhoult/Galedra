# Audits, audit schedules, and reputation events (spec 02 §3.4). All three are
# projections rebuilt by replay; audit_schedules is deterministic in the log at
# the evaluated seq (05 §9).
class CreateAudits < ActiveRecord::Migration[8.1]
  def change
    create_table :audits, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :target_contribution_id, null: false
      t.uuid :auditor_contributor_id, null: false
      t.string :audit_type, null: false
      t.string :result, null: false
      t.integer :effort_seconds
      t.string :task_type, null: false
      t.string :domain, null: false
      t.text :note
      t.bigint :created_seq, null: false
      t.bigint :invalidated_seq
    end
    add_index :audits, :contribution_id, unique: true
    add_index :audits, :target_contribution_id
    add_index :audits, :auditor_contributor_id

    create_table :audit_schedules, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.bigint :evaluated_at_seq, null: false
      t.string :policy_version, null: false
      t.jsonb :inputs, null: false, default: {}
      t.string :audit_probability, null: false
      t.boolean :sampled, null: false
      t.bigint :forced_by_seq
      t.bigint :rescheduled_by_seq
    end
    add_index :audit_schedules, :contribution_id, unique: true
    add_index :audit_schedules, :sampled

    create_table :reputation_events, id: :uuid, default: nil do |t|
      t.uuid :contribution_id, null: false
      t.uuid :contributor_id, null: false
      t.uuid :principal_contributor_id
      t.string :task_type, null: false
      t.string :domain, null: false
      t.uuid :audit_id, null: false
      t.decimal :alpha_delta, precision: 6, scale: 2, null: false
      t.decimal :beta_delta, precision: 6, scale: 2, null: false
      t.bigint :created_seq, null: false
      t.bigint :invalidated_seq
    end
    add_index :reputation_events, [ :contributor_id, :task_type, :domain ]
    add_index :reputation_events, [ :principal_contributor_id, :task_type, :domain ]
    add_index :reputation_events, :audit_id
  end
end
