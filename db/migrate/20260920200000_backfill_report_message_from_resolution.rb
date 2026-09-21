# frozen_string_literal: true

# Every answer given before the exchange existed was a single `resolution`
# field. The report page now renders the thread and no longer shows that field
# separately, so without this those answers would simply vanish from the page —
# fourteen of them, including the ones explaining a reporter's own withdrawn
# diagnoses.
#
# Dated at updated_at, which is the closest thing to when the answer was given.
# Bound to the tables as they stood at this point in history, not to the
# application's models. `ReportMessage` was renamed to `ThreadTurn` the same
# evening, and a migration that names a model is a migration that breaks the
# moment the model moves: `db:migrate` from empty died on an uninitialized
# constant, which `db:prepare` hid because a fresh database loads schema.rb.
class BackfillReportMessageFromResolution < ActiveRecord::Migration[8.1]
  class Message < ActiveRecord::Base
    self.table_name = "report_messages"
  end

  def up
    { "BugReport" => "bug_reports", "FeatureRequest" => "feature_requests" }.each do |type, table|
      select_all("SELECT id, resolution, updated_at FROM #{table} WHERE resolution IS NOT NULL AND resolution <> ''").each do |row|
        next if Message.exists?(report_type: type, report_id: row["id"], author_kind: "maintainer")

        Message.create!(id: SecureRandom.uuid_v7, report_type: type, report_id: row["id"], author_kind: "maintainer",
                        body: row["resolution"], created_at: row["updated_at"], updated_at: row["updated_at"])
      end
    end
  end

  def down
    # The backfilled turns are indistinguishable from answers given since, and
    # deleting by heuristic would take real ones with them.
    raise ActiveRecord::IrreversibleMigration
  end
end
