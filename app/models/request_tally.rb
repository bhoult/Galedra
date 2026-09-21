# Stage 40: how often one controller action was asked for in one hour, and what
# it cost in total. Outside the log; derived, prunable, and carrying nothing
# about who made the request.
class RequestTally < ApplicationRecord
  scope :for_hour, ->(hour) { where(hour: hour) }
  scope :since, ->(time) { where(hour: time..) }

  def mean_ms = calls.positive? ? (total_ms / calls).round(1) : 0
  def statements_per_call = calls.positive? ? (statements.to_f / calls).round(1) : 0
end
