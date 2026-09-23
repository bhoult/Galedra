# frozen_string_literal: true

# Stage 42 §9. An answer saying something is fixed was prose the filer could
# not check without cloning the repository, and twice in one day the prose was
# wrong in a way nobody could see: a repro naming a tool that never had the bug,
# and commit ids that changed when the commits were rebased before pushing. So a
# maintainer's turn can carry where the fix is and the exact call to re-run, as
# fields, and get_report returns them to the filer as fields.
class AddFixedInAndReproToThreadTurns < ActiveRecord::Migration[8.1]
  def change
    add_column :thread_turns, :fixed_in, :string
    add_column :thread_turns, :repro, :text
  end
end
