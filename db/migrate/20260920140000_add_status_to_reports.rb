# frozen_string_literal: true

# Triage for bug reports and feature requests (owner request, 2026-09-20).
#
# Both live outside the log and never reach scoring, so a mutable status column
# is the right shape: this is a maintainer's working list, not a record of what
# was claimed. Nothing here is signed and nothing here is append-only.
class AddStatusToReports < ActiveRecord::Migration[8.1]
  def change
    %i[bug_reports feature_requests].each do |table|
      add_column table, :status, :string, default: "OPEN", null: false
      add_index table, [ :status, :created_at ]
    end
  end
end
