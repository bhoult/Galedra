# The stored sampling decision for a contribution (spec 02 §3.4, 05 §9):
# inputs as of its own seq, the probability, and whether the hash sampled it.
class AuditSchedule < ApplicationRecord
  include Projection

  belongs_to :contribution

  def forced? = forced_by_seq.present?
  def due? = sampled || forced? || rescheduled_by_seq.present?
end
