# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_17_230000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "agent_delegations", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "created_seq", null: false
    t.uuid "delegate_contributor_id", null: false
    t.string "delegation_signature", null: false
    t.integer "max_tasks_per_day"
    t.jsonb "permissions", default: {}, null: false
    t.uuid "principal_contributor_id", null: false
    t.bigint "revoked_seq"
    t.timestamptz "valid_from", null: false
    t.timestamptz "valid_until", null: false
    t.index ["delegate_contributor_id"], name: "index_agent_delegations_on_delegate_contributor_id"
    t.index ["principal_contributor_id"], name: "index_agent_delegations_on_principal_contributor_id"
  end

  create_table "claim_edges", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "accepted_seq"
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.uuid "from_claim_id", null: false
    t.bigint "invalidated_seq"
    t.string "relationship_type", null: false
    t.uuid "to_claim_id", null: false
    t.index ["contribution_id"], name: "index_claim_edges_on_contribution_id"
    t.index ["created_seq"], name: "index_claim_edges_on_created_seq"
    t.index ["from_claim_id"], name: "index_claim_edges_on_from_claim_id"
    t.index ["invalidated_seq"], name: "index_claim_edges_on_invalidated_seq"
    t.index ["to_claim_id"], name: "index_claim_edges_on_to_claim_id"
  end

  create_table "claim_evaluability_settings", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "accepted_seq"
    t.uuid "claim_id", null: false
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.bigint "invalidated_seq"
    t.string "not_evaluable_reason"
    t.boolean "truth_evaluable", null: false
    t.index ["claim_id"], name: "index_claim_evaluability_settings_on_claim_id"
    t.index ["contribution_id"], name: "index_claim_evaluability_settings_on_contribution_id"
  end

  create_table "claim_merges", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "accepted_seq"
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.uuid "from_claim_id", null: false
    t.uuid "into_claim_id", null: false
    t.bigint "invalidated_seq"
    t.index ["contribution_id"], name: "index_claim_merges_on_contribution_id"
    t.index ["from_claim_id"], name: "index_claim_merges_on_from_claim_id"
    t.index ["into_claim_id"], name: "index_claim_merges_on_into_claim_id"
  end

  create_table "claims", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "accepted_seq"
    t.text "canonical_text", null: false
    t.string "claim_type", null: false
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.bigint "invalidated_seq"
    t.uuid "merged_into_id"
    t.string "not_evaluable_reason"
    t.jsonb "qualifiers", default: {}, null: false
    t.string "status", default: "ACTIVE", null: false
    t.uuid "superseded_by_id"
    t.uuid "supersedes_claim_id"
    t.boolean "truth_evaluable", null: false
    t.index "to_tsvector('english'::regconfig, canonical_text)", name: "index_claims_on_canonical_text_fts", using: :gin
    t.index ["accepted_seq"], name: "index_claims_on_accepted_seq"
    t.index ["canonical_text"], name: "index_claims_on_canonical_text_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["claim_type"], name: "index_claims_on_claim_type"
    t.index ["contribution_id"], name: "index_claims_on_contribution_id"
    t.index ["created_seq"], name: "index_claims_on_created_seq"
    t.index ["invalidated_seq"], name: "index_claims_on_invalidated_seq"
    t.index ["supersedes_claim_id"], name: "index_claims_on_supersedes_claim_id"
  end

  create_table "contributions", id: :uuid, default: nil, force: :cascade do |t|
    t.string "action_class", null: false
    t.string "action_type", null: false
    t.timestamptz "client_created_at", null: false
    t.uuid "contributor_id"
    t.string "current_status", null: false
    t.string "custody", null: false
    t.string "entry_hash", null: false
    t.jsonb "envelope"
    t.string "envelope_hash", null: false
    t.string "idempotency_key", null: false
    t.jsonb "payload"
    t.string "payload_hash", null: false
    t.string "prev_hash", null: false
    t.timestamptz "received_at", null: false
    t.bigint "redacted_by_seq"
    t.bigint "seq", null: false
    t.string "server_signature", null: false
    t.string "signature", null: false
    t.string "signer_key_id", null: false
    t.jsonb "software"
    t.uuid "task_id"
    t.string "task_packet_hash"
    t.index ["action_type"], name: "index_contributions_on_action_type"
    t.index ["contributor_id", "seq"], name: "index_contributions_on_contributor_id_and_seq"
    t.index ["entry_hash"], name: "index_contributions_on_entry_hash", unique: true
    t.index ["idempotency_key"], name: "index_contributions_on_idempotency_key", unique: true
    t.index ["seq"], name: "index_contributions_on_seq", unique: true
    t.index ["signer_key_id"], name: "index_contributions_on_signer_key_id"
  end

  create_table "contributors", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "created_seq"
    t.string "display_name"
    t.string "identity_tier", default: "PSEUDONYMOUS", null: false
    t.string "key_id", null: false
    t.string "kind", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "public_key", null: false
    t.bigint "revoked_seq"
    t.index ["key_id"], name: "index_contributors_on_key_id", unique: true
  end

  create_table "custodied_keys", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "contributor_id", null: false
    t.datetime "created_at", null: false
    t.text "encrypted_private_key", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["contributor_id"], name: "index_custodied_keys_on_contributor_id", unique: true
    t.index ["user_id"], name: "index_custodied_keys_on_user_id"
  end

  create_table "evidence_claim_links", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "accepted_seq"
    t.uuid "claim_id", null: false
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.string "direction", null: false
    t.uuid "evidence_item_id", null: false
    t.integer "interpretive_steps", default: 0, null: false
    t.bigint "invalidated_seq"
    t.text "note"
    t.string "relevance_strength", null: false
    t.uuid "supersedes_link_id"
    t.index ["claim_id", "created_seq"], name: "index_evidence_claim_links_on_claim_id_and_created_seq"
    t.index ["contribution_id"], name: "index_evidence_claim_links_on_contribution_id"
    t.index ["created_seq"], name: "index_evidence_claim_links_on_created_seq"
    t.index ["evidence_item_id"], name: "index_evidence_claim_links_on_evidence_item_id"
    t.index ["invalidated_seq"], name: "index_evidence_claim_links_on_invalidated_seq"
    t.index ["supersedes_link_id"], name: "index_evidence_claim_links_on_supersedes_link_id"
  end

  create_table "evidence_items", id: :uuid, default: nil, force: :cascade do |t|
    t.jsonb "assessment", default: {}, null: false
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.uuid "independence_group_id"
    t.bigint "invalidated_seq"
    t.string "observation_type", null: false
    t.uuid "source_location_id", null: false
    t.text "statement", null: false
    t.jsonb "structured_value"
    t.index ["contribution_id"], name: "index_evidence_items_on_contribution_id"
    t.index ["created_seq"], name: "index_evidence_items_on_created_seq"
    t.index ["independence_group_id"], name: "index_evidence_items_on_independence_group_id"
    t.index ["invalidated_seq"], name: "index_evidence_items_on_invalidated_seq"
    t.index ["source_location_id"], name: "index_evidence_items_on_source_location_id"
  end

  create_table "independence_group_assignments", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "accepted_seq"
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.uuid "evidence_item_id", null: false
    t.uuid "independence_group_id", null: false
    t.bigint "invalidated_seq"
    t.index ["contribution_id"], name: "index_independence_group_assignments_on_contribution_id"
    t.index ["created_seq"], name: "index_independence_group_assignments_on_created_seq"
    t.index ["evidence_item_id"], name: "index_independence_group_assignments_on_evidence_item_id"
    t.index ["invalidated_seq"], name: "index_independence_group_assignments_on_invalidated_seq"
  end

  create_table "independence_groups", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "accepted_seq"
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.text "description"
    t.string "group_type", null: false
    t.bigint "invalidated_seq"
    t.index ["contribution_id"], name: "index_independence_groups_on_contribution_id"
    t.index ["created_seq"], name: "index_independence_groups_on_created_seq"
    t.index ["invalidated_seq"], name: "index_independence_groups_on_invalidated_seq"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_batch_executions", force: :cascade do |t|
    t.bigint "batch_id", null: false
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.index ["batch_id"], name: "index_solid_queue_batch_executions_on_batch_id"
    t.index ["job_id"], name: "index_solid_queue_batch_executions_on_job_id", unique: true
  end

  create_table "solid_queue_batches", force: :cascade do |t|
    t.string "active_job_batch_id"
    t.integer "completed_jobs", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.datetime "enqueued_at"
    t.datetime "failed_at"
    t.integer "failed_jobs", default: 0, null: false
    t.datetime "finished_at"
    t.text "metadata"
    t.text "on_failure"
    t.text "on_finish"
    t.text "on_success"
    t.integer "total_jobs", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_batch_id"], name: "index_solid_queue_batches_on_active_job_batch_id", unique: true
    t.index ["finished_at"], name: "index_solid_queue_batches_on_finished_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.bigint "batch_id"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["batch_id"], name: "index_solid_queue_jobs_on_batch_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "source_locations", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.text "excerpt"
    t.string "excerpt_hash"
    t.bigint "invalidated_seq"
    t.jsonb "locator", default: {}, null: false
    t.string "locator_type", null: false
    t.uuid "source_id", null: false
    t.index ["contribution_id"], name: "index_source_locations_on_contribution_id"
    t.index ["created_seq"], name: "index_source_locations_on_created_seq"
    t.index ["invalidated_seq"], name: "index_source_locations_on_invalidated_seq"
    t.index ["source_id"], name: "index_source_locations_on_source_id"
  end

  create_table "sources", id: :uuid, default: nil, force: :cascade do |t|
    t.string "canonical_uri"
    t.text "content"
    t.string "content_hash"
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.string "creator"
    t.jsonb "external_ids", default: {}, null: false
    t.bigint "invalidated_seq"
    t.string "license"
    t.string "lineage_key"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "previous_version_id"
    t.date "publication_date"
    t.string "publisher"
    t.timestamptz "retrieved_at"
    t.string "source_type", null: false
    t.string "title", null: false
    t.index ["contribution_id"], name: "index_sources_on_contribution_id"
    t.index ["created_seq"], name: "index_sources_on_created_seq"
    t.index ["invalidated_seq"], name: "index_sources_on_invalidated_seq"
    t.index ["lineage_key"], name: "index_sources_on_lineage_key"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "claim_edges", "claims", column: "from_claim_id"
  add_foreign_key "claim_edges", "claims", column: "to_claim_id"
  add_foreign_key "claim_evaluability_settings", "claims"
  add_foreign_key "claim_merges", "claims", column: "from_claim_id"
  add_foreign_key "claim_merges", "claims", column: "into_claim_id"
  add_foreign_key "claims", "claims", column: "supersedes_claim_id"
  add_foreign_key "custodied_keys", "users"
  add_foreign_key "evidence_claim_links", "claims"
  add_foreign_key "evidence_claim_links", "evidence_claim_links", column: "supersedes_link_id"
  add_foreign_key "evidence_claim_links", "evidence_items"
  add_foreign_key "evidence_items", "independence_groups"
  add_foreign_key "evidence_items", "source_locations"
  add_foreign_key "independence_group_assignments", "evidence_items"
  add_foreign_key "independence_group_assignments", "independence_groups"
  add_foreign_key "sessions", "users"
  add_foreign_key "solid_queue_batch_executions", "solid_queue_batches", column: "batch_id", on_delete: :cascade
  add_foreign_key "solid_queue_batch_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "source_locations", "sources"
end
