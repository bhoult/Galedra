# frozen_string_literal: true

# Stage 34: whether this task was opened as an explicit request for a blind
# check by someone else, as `open_task` does, rather than opened routinely
# alongside a recording.
#
# Stage 19 says whoever asks for a blind check does not perform it, and that is
# right for a request someone deliberately made. It is not right for the
# verification tasks that open automatically whenever claims are recorded: those
# are opened by the recorder as a matter of course, and treating them as the
# recorder's own blind request is what left a solo investigation unfinishable.
# created_by cannot tell the two apart, because it is set in both cases.
class AddBlindRequestedToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :blind_requested, :boolean, default: false, null: false
  end
end
