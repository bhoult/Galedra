# frozen_string_literal: true

# Why a report was closed, not just that it was (owner request, 2026-09-20).
#
# A status on its own tells the next reader nothing about whether the thing
# reported was fixed, was working as intended, or was set aside — and a list of
# closed items with no reasons is the kind of record that misleads whoever
# inherits it.
class AddResolutionToReports < ActiveRecord::Migration[8.1]
  def change
    add_column :bug_reports, :resolution, :text
    add_column :feature_requests, :resolution, :text
  end
end
