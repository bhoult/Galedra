# frozen_string_literal: true

# Fields that invite doubt, because the filing path only invited a story
# (reported by an assistant in 01a0c05d-db76, after it filed three wrong
# diagnoses in one session and caught each by luck).
#
# happened, expected, steps and last_error all ask for narrative. None asks what
# was checked and did not explain it, or how sure the filer is that their cause
# is the cause. A report with a confident fiction in it sends a maintainer
# digging where nothing is wrong, which happened twice in one evening.
class AddDoubtToBugReports < ActiveRecord::Migration[8.1]
  def change
    add_column :bug_reports, :suspected_cause, :text
    add_column :bug_reports, :ruled_out, :text
    add_column :bug_reports, :confidence, :string
  end
end
