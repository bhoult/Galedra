# frozen_string_literal: true

# A report is a conversation, not a drop box (owner request, 2026-09-20).
#
# An assistant filed a confidently wrong diagnosis, caught it a call later by
# chance, filed a correction, and could neither link the two nor learn whether
# either had been read — while a maintainer reading the first would go digging
# for a red herring it had authored
# (docs/experiments/2026-09-20-second-connector-run.md). Filing was one-way, so
# a wrong report stayed wrong and an answer never reached the reporter.
#
# Each turn is a row: who said it, what they said, and — when the reporter is
# answering a maintainer — whether the resolution actually satisfied them. The
# status follows from the exchange rather than from one side's opinion, so
# "closed" means both sides agreed it was.
class CreateReportMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :report_messages, id: :uuid, default: nil do |t|
      t.string :report_type, null: false
      t.uuid :report_id, null: false
      t.string :author_kind, null: false
      t.uuid :assistant_token_id
      t.uuid :user_id
      t.text :body, null: false
      # Only a reporter answering a maintainer sets this; nil elsewhere.
      t.boolean :satisfied
      t.datetime :created_at, null: false
    end
    add_index :report_messages, [ :report_type, :report_id, :created_at ]

    # DONE meant "a maintainer dealt with it", which is now ANSWERED: nobody has
    # asked the reporter whether the answer was any good. CLOSED is reserved for
    # the two sides agreeing.
    reversible do |dir|
      dir.up do
        execute "UPDATE bug_reports SET status = 'ANSWERED' WHERE status = 'DONE'"
        execute "UPDATE feature_requests SET status = 'ANSWERED' WHERE status = 'DONE'"
      end
      dir.down do
        execute "UPDATE bug_reports SET status = 'DONE' WHERE status IN ('ANSWERED','CLOSED')"
        execute "UPDATE feature_requests SET status = 'DONE' WHERE status IN ('ANSWERED','CLOSED')"
      end
    end
  end
end
