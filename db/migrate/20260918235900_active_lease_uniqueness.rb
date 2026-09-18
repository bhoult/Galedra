# Stage 18: uniqueness is per active lease (04 §7: "one active lease per
# (task, contributor) and per (task, principal)"), so a contributor whose lease
# expired or was released can take the task again; a submitted slot still blocks.
class ActiveLeaseUniqueness < ActiveRecord::Migration[8.1]
  def change
    remove_index :task_assignments, [ :task_id, :contributor_id ], unique: true
    remove_index :task_assignments, [ :task_id, :principal_contributor_id ], unique: true
    add_index :task_assignments, [ :task_id, :contributor_id ], unique: true, where: "status IN ('LEASED', 'SUBMITTED')", name: "index_task_assignments_active_per_contributor"
    add_index :task_assignments, [ :task_id, :principal_contributor_id ], unique: true, where: "status IN ('LEASED', 'SUBMITTED')", name: "index_task_assignments_active_per_principal"
  end
end
