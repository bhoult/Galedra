# frozen_string_literal: true

module Tasks
  # Recomputes one task's status from its assignments.
  #
  # This lived inside tasks/lease.rb, where Zeitwerk could not find it: the
  # constant only resolved once something had referenced Tasks::Lease for another
  # reason. A web request always had, so nothing showed. `bin/rails ledger:replay`
  # had not, so replay died on the first TASK_RESULT it applied, and had done
  # since Stage 25 — which meant Invariant 2 was not being checked at all.
  module Status
    def self.refresh!(task)
      task.reload
      status = if task.status == "CANCELLED" then "CANCELLED"
      elsif task.submitted_assignments.count >= task.required_assignments then "COMPLETE"
      elsif task.open_slots <= 0 then "LEASED"
      else "OPEN"
      end
      task.update!(status: status) if task.status != status
      task
    end
  end
end
