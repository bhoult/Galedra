# A unit of agent work (spec 02 §3.4, 04 §2): a server-signed packet with the
# smallest sufficient context, leased to contributors, answered by TASK_RESULT
# contributions.
class Task < ApplicationRecord
  STATUSES = %w[OPEN LEASED COMPLETE EXPIRED CANCELLED].freeze
  TARGET_TYPES = %w[CLAIM SOURCE INFERENCE].freeze

  has_many :assignments, class_name: "TaskAssignment", dependent: nil

  validates :task_type, inclusion: { in: ->(_) { Tasks::Types::ALL } }
  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :domain, inclusion: { in: ->(_) { Audits::Policy.domains } }

  def target
    case target_type
    when "CLAIM" then Claim.find(target_id)
    when "INFERENCE" then Inference.find(target_id)
    else Source.find(target_id)
    end
  end

  def spec = Tasks::Types.spec(task_type)

  def active_assignments
    assignments.where(status: "LEASED").where("lease_expires_at > ?", Time.current)
  end

  def submitted_assignments = assignments.where(status: "SUBMITTED")

  def open_slots
    required_assignments - active_assignments.count - submitted_assignments.count
  end

  # Open slots for a whole set in one query, as {task_id => slots}, using the
  # same predicate #open_slots uses so the answers cannot differ: a slot is taken
  # by a live lease or by a submission. A listing asked every task instead, twice
  # — once to filter and once to total — at two queries a time, which was most of
  # 3,714 statements over ~840 tasks
  # (docs/experiments/2026-09-20-second-connector-run.md, finding 4).
  #
  # Deliberately NOT memoised on the instance: Tasks::Lease reads open_slots,
  # creates an assignment, then reads it again to decide whether the task is now
  # fully leased, and a memo makes the second read stale. The suite caught it.
  def self.open_slots_for(tasks)
    tasks = tasks.to_a
    return {} if tasks.empty?

    taken = TaskAssignment.where(task_id: tasks.map(&:id))
                          .where("(status = 'LEASED' AND lease_expires_at > :now) OR status = 'SUBMITTED'", now: Time.current)
                          .group(:task_id).count
    tasks.to_h { |t| [ t.id, t.required_assignments - taken.fetch(t.id, 0) ] }
  end

  # Results are revealed only once every slot is submitted, or once leases have
  # expired with none still live (04 §3.1). An unleased open slot keeps it blind.
  def closed?
    return true if submitted_assignments.count >= required_assignments

    submitted_assignments.any? && active_assignments.none? && assignments.where(status: "EXPIRED").any?
  end
end
