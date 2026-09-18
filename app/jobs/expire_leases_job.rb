# Expires overdue leases (spec 04 §7); Solid Queue can run it on a schedule.
class ExpireLeasesJob < ApplicationJob
  queue_as :default

  def perform
    Tasks::Lease.expire_stale!
  end
end
