# frozen_string_literal: true

# `users` has a bigint primary key and these columns were uuid, so every
# maintainer's turn on a bug report or a feature request since the register
# gained an exchange has recorded no author at all: 62 turns, nil every time,
# with no error raised. Assigning an integer to a uuid column casts to nil
# quietly, which is why nothing ever failed and nobody noticed.
#
# Found by writing a spec that asserted a person's turn carries the person
# (Stage 37). The register's own specs had never asserted it.
#
# Safe to change in place: every existing value is nil, so nothing is lost that
# was not already lost.
class FixUserIdTypeOnTurns < ActiveRecord::Migration[8.1]
  def up
    change_column :thread_turns, :user_id, :bigint, using: "NULL::bigint"
    change_column :determination_threads, :user_id, :bigint, using: "NULL::bigint"
  end

  def down
    change_column :thread_turns, :user_id, :uuid, using: "NULL::uuid"
    change_column :determination_threads, :user_id, :uuid, using: "NULL::uuid"
  end
end
