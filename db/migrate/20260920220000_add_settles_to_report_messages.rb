# frozen_string_literal: true

# A maintainer's turn that deliberately does not settle anything.
#
# The three-hour timeout (owner request, 2026-09-20) exists because a reporter
# may never come back, and its wording was "if the reporter does not respond for
# three hours *and you think it is settled*". `answer!` had no way to say the
# second half: every maintainer turn armed the timeout. So a report answered
# with "this stays open until Stage 36 ships" would close itself three hours
# later, on a fix that has not been written, and the filer who agreed to hold it
# open would find it closed.
#
# Default true, because most answers do settle. False is the deliberate case.
class AddSettlesToReportMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :report_messages, :settles, :boolean, null: false, default: true
  end
end
