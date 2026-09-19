# Stage 21: tasks know the section they serve (an extraction task on a leaf,
# a verification task on a placed claim) so work can be filtered by outline;
# a cancelled task says why; an investigation may stand for a whole outline.
class TasksAndInvestigationsSections < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :section_id, :uuid
    add_column :tasks, :cancelled_reason, :string
    add_index :tasks, :section_id
    add_column :investigations, :section_id, :uuid
  end
end
