# A unit of agent work (spec 02 §3.4, 04 §2): a server-signed packet with the
# smallest sufficient context, leased to contributors, answered by TASK_RESULT
# contributions.
class Task < ApplicationRecord
  STATUSES = %w[OPEN LEASED COMPLETE EXPIRED CANCELLED].freeze
  TARGET_TYPES = %w[CLAIM SOURCE].freeze

  has_many :assignments, class_name: "TaskAssignment", dependent: nil

  validates :task_type, inclusion: { in: ->(_) { Tasks::Types::ALL } }
  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :domain, inclusion: { in: ->(_) { Audits::Policy.domains } }

  def target
    target_type == "CLAIM" ? Claim.find(target_id) : Source.find(target_id)
  end

  def spec = Tasks::Types.spec(task_type)

  def active_assignments
    assignments.where(status: "LEASED").where("lease_expires_at > ?", Time.current)
  end

  def submitted_assignments = assignments.where(status: "SUBMITTED")

  def open_slots
    required_assignments - active_assignments.count - submitted_assignments.count
  end

  # Results are revealed only once every slot is submitted, or once leases have
  # expired with none still live (04 §3.1). An unleased open slot keeps it blind.
  def closed?
    return true if submitted_assignments.count >= required_assignments

    submitted_assignments.any? && active_assignments.none? && assignments.where(status: "EXPIRED").any?
  end
end
