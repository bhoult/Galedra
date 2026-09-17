# The append-only contribution log (spec 02 §3.1). Payload and envelope are
# nullable only so a legally compelled TAKEDOWN (02 §5, Stage 4) can remove the
# bytes while the hashes and chain remain.
class CreateContributions < ActiveRecord::Migration[8.1]
  def change
    create_table :contributions, id: :uuid, default: nil do |t|
      t.bigint :seq, null: false
      t.string :signer_key_id, null: false
      t.uuid :contributor_id
      t.string :action_class, null: false
      t.string :action_type, null: false
      t.jsonb :payload
      t.string :payload_hash, null: false
      t.jsonb :envelope
      t.string :envelope_hash, null: false
      t.string :signature, null: false
      t.uuid :task_id
      t.string :task_packet_hash
      t.jsonb :software
      t.string :custody, null: false
      t.bigint :redacted_by_seq
      t.timestamptz :client_created_at, null: false
      t.timestamptz :received_at, null: false
      t.string :prev_hash, null: false
      t.string :entry_hash, null: false
      t.string :server_signature, null: false
      t.string :idempotency_key, null: false
      t.string :current_status, null: false
    end

    add_index :contributions, :seq, unique: true
    add_index :contributions, :entry_hash, unique: true
    add_index :contributions, :idempotency_key, unique: true
    add_index :contributions, [ :contributor_id, :seq ]
    add_index :contributions, :signer_key_id
    add_index :contributions, :action_type
  end
end
