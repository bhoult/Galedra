# frozen_string_literal: true

module Tasks
  # Task facts for a contribution's task_id (reputation buckets, spec 02 §3.4).
  module Lookup
    def self.for(task_id)
      task = Task.find_by(id: task_id)
      task && { task_type: task.task_type, domain: task.domain }
    end
  end
end
