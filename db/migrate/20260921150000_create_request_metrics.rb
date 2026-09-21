# Stage 40: how long the node took, and how often it was asked.
#
# Both tables are derived operational data, outside the log and outside
# Ledger::TableDigest, like claim_scores and bug_reports. Neither holds a client
# IP or a user identity: Galedra deliberately records no client addresses, and a
# performance table is not a reason to start.
class CreateRequestMetrics < ActiveRecord::Migration[8.1]
  def change
    # One row per (action, hour), upserted on every request. This is the half
    # that says what the node is actually asked for, which decides whether a
    # slow page is worth anyone's time.
    create_table :request_tallies, id: :uuid, default: nil do |t|
      t.string :action, null: false
      t.timestamptz :hour, null: false
      t.bigint :calls, null: false, default: 0
      t.bigint :statements, null: false, default: 0
      t.bigint :slow_calls, null: false, default: 0
      t.decimal :total_ms, precision: 14, scale: 2, null: false, default: 0
      t.decimal :max_ms, precision: 10, scale: 2, null: false, default: 0
      t.timestamptz :created_at, null: false
      t.timestamptz :updated_at, null: false
      t.index [ :action, :hour ], unique: true
      t.index :hour
    end

    # One row per request over the threshold, which is rare by construction.
    # head_seq is what keeps the row meaningful later: a timing without the
    # corpus it was taken against is not evidence (docs/profiler/README.md).
    create_table :request_samples, id: :uuid, default: nil do |t|
      t.string :action, null: false
      t.string :method, null: false
      t.integer :status
      t.decimal :duration_ms, precision: 10, scale: 2, null: false
      t.decimal :db_ms, precision: 10, scale: 2
      t.decimal :view_ms, precision: 10, scale: 2
      t.integer :statements, null: false, default: 0
      t.bigint :head_seq
      t.string :request_id
      t.timestamptz :recorded_at, null: false
      t.index [ :action, :recorded_at ]
      t.index :recorded_at
      t.index :duration_ms
    end
  end
end
