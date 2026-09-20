# frozen_string_literal: true

# Every answer given before the exchange existed was a single `resolution`
# field. The report page now renders the thread and no longer shows that field
# separately, so without this those answers would simply vanish from the page —
# fourteen of them, including the ones explaining a reporter's own withdrawn
# diagnoses.
#
# Dated at updated_at, which is the closest thing to when the answer was given.
class BackfillReportMessageFromResolution < ActiveRecord::Migration[8.1]
  def up
    [ BugReport, FeatureRequest ].each do |model|
      model.where.not(resolution: [ nil, "" ]).find_each do |row|
        next if ReportMessage.exists?(report: row, author_kind: "maintainer")

        ReportMessage.create!(report: row, author_kind: "maintainer", body: row.resolution, created_at: row.updated_at)
      end
    end
  end

  def down
    # The backfilled turns are indistinguishable from answers given since, and
    # deleting by heuristic would take real ones with them.
    raise ActiveRecord::IrreversibleMigration
  end
end
