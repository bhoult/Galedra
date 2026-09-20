# frozen_string_literal: true

# The write cap becomes hourly rather than daily (owner request, 2026-09-19).
#
# A first pass over a two-hour source costs roughly 1,600 signed writes, so a
# daily cap of 1,000 stopped an investigation about two thirds of the way in and
# left it stopped until the next calendar day. The cap is there to bound a
# runaway agent, not to make a legitimate long job impossible, and an hour is the
# window that does the first without the second.
#
# The column on agent_delegations is renamed too, because its value is written
# into a signed DELEGATE payload: leaving it called max_tasks_per_day while it
# means per hour would put a false statement in the log. Contributions already
# signed keep the old key, and Ledger::Appliers::Delegate reads either, so replay
# still reproduces every historical row.
class ChangeAgentCapsToHourly < ActiveRecord::Migration[8.1]
  def up
    rename_column :assistant_tokens, :daily_cap, :hourly_cap
    change_column_default :assistant_tokens, :hourly_cap, from: 200, to: 500
    rename_column :agent_delegations, :max_tasks_per_day, :max_tasks_per_hour
  end

  def down
    rename_column :agent_delegations, :max_tasks_per_hour, :max_tasks_per_day
    change_column_default :assistant_tokens, :hourly_cap, from: 500, to: 200
    rename_column :assistant_tokens, :hourly_cap, :daily_cap
  end
end
