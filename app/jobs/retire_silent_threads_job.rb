# frozen_string_literal: true

# A thread nobody has touched leaves the work list. It is dormant, not
# concluded: nothing was agreed, no outcome is recorded, no task is opened or
# cancelled, and any turn revives it with its turns and votes intact.
#
# Stage 26 built a retention job and scheduled it nowhere, so it only ever ran
# when someone typed the rake task. This one is scheduled in the same commit
# that adds it.
class RetireSilentThreadsJob < ApplicationJob
  queue_as :background

  def perform = DeterminationThread.retire_silent!
end
