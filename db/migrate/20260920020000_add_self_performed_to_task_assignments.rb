# frozen_string_literal: true

# Stage 34: whether a check was performed by the principal that recorded the
# thing being checked.
#
# Recorded when the lease is taken rather than derived later by comparing
# principals, because that comparison does not stay stable: keys are adopted,
# contributors merge, and a fact about what happened must not be recomputed from
# a world that has since changed.
class AddSelfPerformedToTaskAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :task_assignments, :self_performed, :boolean, default: false, null: false
    add_index :task_assignments, [ :task_id, :self_performed ]
  end
end
