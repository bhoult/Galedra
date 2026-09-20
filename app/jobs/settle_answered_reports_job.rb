# frozen_string_literal: true

# Closes bug reports and feature requests whose answer nobody came back on
# within Triageable::UNANSWERED_AFTER. A reporter may never return, and a report
# cannot wait on someone who has gone; the reporter can still disagree
# afterwards and it reopens.
class SettleAnsweredReportsJob < ApplicationJob
  queue_as :default

  def perform
    BugReport.settle_unanswered!
    FeatureRequest.settle_unanswered!
  end
end
