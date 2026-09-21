# frozen_string_literal: true

# One turn table for every conversation in Galedra (Stage 37).
#
# `report_messages` already holds turns on bug reports and feature requests
# through a polymorphic parent, with clipping, an author kind and a verdict from
# the filer. Threads on determinations need exactly that and nothing more, so the
# table generalises rather than being copied: two implementations of a
# conversation drift within a day, and this project has watched a guidance line
# and a refusal hint say different things about the same rule on the same day.
#
# `verdict` is new. A register turn carries `satisfied`, which is a yes or no
# about someone's answer; a thread turn carries a named outcome that three
# principals must agree on. They are different questions and they get different
# columns rather than one overloaded one.
class RenameReportMessagesToThreadTurns < ActiveRecord::Migration[8.1]
  def change
    rename_table :report_messages, :thread_turns
    rename_column :thread_turns, :report_id, :thread_id
    rename_column :thread_turns, :report_type, :thread_type
    add_column :thread_turns, :verdict, :string
  end
end
