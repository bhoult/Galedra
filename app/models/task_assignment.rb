# One contributor's lease on a task (spec 02 §3.4). Unique per contributor and
# per principal so one principal cannot fill every independent slot.
class TaskAssignment < ApplicationRecord
  STATUSES = %w[LEASED SUBMITTED EXPIRED RELEASED].freeze

  belongs_to :task
  belongs_to :contributor
  belongs_to :principal, class_name: "Contributor", foreign_key: :principal_contributor_id, inverse_of: false

  validates :status, inclusion: { in: STATUSES }

  # A contributor may hold an expired or released row and a later live one.
  def self.latest_for(task_id, contributor_id)
    where(task_id: task_id, contributor_id: contributor_id).order(:created_at).last
  end

  def live?
    status == "LEASED" && lease_expires_at > Time.current
  end
end
