# frozen_string_literal: true

# A conversation about how a determination was made (Stage 37).
#
# Outside the log and carrying no version at all: no seq, no snapshot, no model,
# no replay. A thread guides evidence gathering; it does not determine it, so
# nothing here is an input to anything the scorer reads, and `ledger:replay`
# neither knows nor cares that these rows exist.
#
# `digest` and `count` are the register's dedup shape: the same concern about the
# same determination collapses onto one thread with a count rather than opening a
# second, and the match spans settled threads as well as open ones, which is what
# stops re-filing becoming the endless argument the settlement rule exists to
# end. `cites_thread_id` is the other half of that: a genuinely new concern about
# a settled matter opens a thread that points at the one it revisits.
class CreateDeterminationThreads < ActiveRecord::Migration[8.1]
  def change
    create_table :determination_threads, id: :uuid, default: nil do |t|
      t.string :subject_type, null: false
      t.uuid :subject_id, null: false
      t.text :concern, null: false
      t.string :status, null: false, default: "OPEN"
      t.string :outcome
      t.uuid :assistant_token_id
      t.uuid :user_id
      t.uuid :opener_principal_id
      t.string :digest, null: false
      t.integer :count, null: false, default: 1
      t.uuid :cites_thread_id
      t.datetime :settled_at
      t.datetime :last_turn_at
      t.boolean :anonymous, null: false, default: false
      t.timestamps
    end
    add_index :determination_threads, %i[subject_type subject_id status]
    add_index :determination_threads, :digest
    add_index :determination_threads, :status
  end
end
