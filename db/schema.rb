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

ActiveRecord::Schema[8.1].define(version: 2026_09_19_210001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "affiliation_requests", id: :uuid, default: nil, force: :cascade do |t|
    t.string "confidence"
    t.datetime "created_at", null: false
    t.string "normalized", null: false
    t.string "proposed_slug"
    t.datetime "resolved_at"
    t.bigint "resolved_by_id"
    t.string "resolved_slug"
    t.string "status", default: "PENDING", null: false
    t.string "text", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["status", "normalized"], name: "index_affiliation_requests_on_status_and_normalized"
    t.index ["user_id"], name: "index_affiliation_requests_on_user_id"
  end

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

  create_table "assistant_tokens", id: :uuid, default: nil, force: :cascade do |t|
    t.text "adoption_code"
    t.string "adoption_digest"
    t.uuid "agent_contributor_id", null: false
    t.datetime "created_at", null: false
    t.integer "daily_cap", default: 200, null: false
    t.uuid "delegation_id", null: false
    t.timestamptz "last_used_at"
    t.uuid "principal_contributor_id", null: false
    t.timestamptz "revoked_at"
    t.jsonb "software", default: {}, null: false
    t.string "source_key"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["adoption_digest"], name: "index_assistant_tokens_on_adoption_digest", unique: true
    t.index ["agent_contributor_id"], name: "index_assistant_tokens_on_agent_contributor_id", unique: true
    t.index ["source_key"], name: "index_assistant_tokens_on_source_key", unique: true
    t.index ["token_digest"], name: "index_assistant_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_assistant_tokens_on_user_id"
  end

  create_table "audit_schedules", id: :uuid, default: nil, force: :cascade do |t|
    t.string "audit_probability", null: false
    t.uuid "contribution_id", null: false
    t.bigint "evaluated_at_seq", null: false
    t.bigint "forced_by_seq"
    t.jsonb "inputs", default: {}, null: false
    t.string "policy_version", null: false
    t.bigint "rescheduled_by_seq"
    t.boolean "sampled", null: false
    t.index ["contribution_id"], name: "index_audit_schedules_on_contribution_id", unique: true
    t.index ["sampled"], name: "index_audit_schedules_on_sampled"
  end

  create_table "audits", id: :uuid, default: nil, force: :cascade do |t|
    t.string "audit_type", null: false
    t.uuid "auditor_contributor_id", null: false
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.string "domain", null: false
    t.integer "effort_seconds"
    t.bigint "invalidated_seq"
    t.text "note"
    t.string "result", null: false
    t.uuid "target_contribution_id", null: false
    t.string "task_type", null: false
    t.index ["auditor_contributor_id"], name: "index_audits_on_auditor_contributor_id"
    t.index ["contribution_id"], name: "index_audits_on_contribution_id", unique: true
    t.index ["target_contribution_id"], name: "index_audits_on_target_contribution_id"
  end

  create_table "bug_reports", id: :uuid, default: nil, force: :cascade do |t|
    t.boolean "anonymous", default: false, null: false
    t.uuid "assistant_token_id"
    t.string "context_tool"
    t.integer "count", default: 1, null: false
    t.datetime "created_at", null: false
    t.string "digest", null: false
    t.text "expected"
    t.text "happened", null: false
    t.string "last_error"
    t.text "steps"
    t.datetime "updated_at", null: false
    t.string "url"
    t.bigint "user_id"
    t.index ["created_at"], name: "index_bug_reports_on_created_at"
    t.index ["digest"], name: "index_bug_reports_on_digest"
  end

  create_table "claim_edges", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "accepted_seq"
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.uuid "from_claim_id", null: false
    t.bigint "invalidated_seq"
    t.bigint "redacted_by_seq"
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
    t.bigint "redacted_by_seq"
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
    t.bigint "redacted_by_seq"
    t.index ["contribution_id"], name: "index_claim_merges_on_contribution_id"
    t.index ["from_claim_id"], name: "index_claim_merges_on_from_claim_id"
    t.index ["into_claim_id"], name: "index_claim_merges_on_into_claim_id"
  end

  create_table "claim_placements", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "accepted_seq"
    t.uuid "claim_id", null: false
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.bigint "invalidated_seq"
    t.integer "position", default: 0, null: false
    t.uuid "section_id", null: false
    t.index ["claim_id"], name: "index_claim_placements_on_claim_id"
    t.index ["contribution_id"], name: "index_claim_placements_on_contribution_id"
    t.index ["section_id", "position"], name: "index_claim_placements_on_section_id_and_position"
  end

  create_table "claim_references", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "claim_id", null: false
    t.integer "count", default: 0, null: false
    t.date "day", null: false
    t.string "kind", null: false
    t.index ["claim_id", "kind", "day"], name: "index_claim_references_on_claim_id_and_kind_and_day", unique: true
    t.index ["kind", "day"], name: "index_claim_references_on_kind_and_day"
  end

  create_table "claim_scores", id: :uuid, default: nil, force: :cascade do |t|
    t.string "assessment_state", null: false
    t.uuid "claim_id", null: false
    t.timestamptz "computed_at", null: false
    t.boolean "contested", null: false
    t.integer "contradict_groups", null: false
    t.decimal "probability", precision: 5, scale: 4
    t.boolean "provisional", null: false
    t.decimal "review_coverage", precision: 3, scale: 2, null: false
    t.uuid "scoring_model_id", null: false
    t.bigint "snapshot_seq", null: false
    t.string "stability"
    t.integer "support_groups", null: false
    t.jsonb "trace", null: false
    t.string "trace_hash", null: false
    t.index ["claim_id", "snapshot_seq", "scoring_model_id"], name: "idx_on_claim_id_snapshot_seq_scoring_model_id_48d9ffea91", unique: true
    t.index ["snapshot_seq", "scoring_model_id"], name: "index_claim_scores_on_snapshot_seq_and_scoring_model_id"
  end

  create_table "claim_topics", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "accepted_seq"
    t.uuid "claim_id", null: false
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.bigint "invalidated_seq"
    t.string "note"
    t.uuid "principal_contributor_id"
    t.bigint "replaced_seq"
    t.string "topic", null: false
    t.index ["claim_id", "topic"], name: "index_claim_topics_on_claim_id_and_topic"
    t.index ["contribution_id"], name: "index_claim_topics_on_contribution_id"
    t.index ["topic"], name: "index_claim_topics_on_topic"
  end

  create_table "claims", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "accepted_seq"
    t.text "canonical_text"
    t.string "claim_type", null: false
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.uuid "extracted_from_source_id"
    t.bigint "invalidated_seq"
    t.uuid "merged_into_id"
    t.string "not_evaluable_reason"
    t.jsonb "qualifiers", default: {}, null: false
    t.bigint "redacted_by_seq"
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
    t.index ["extracted_from_source_id"], name: "index_claims_on_extracted_from_source_id"
    t.index ["invalidated_seq"], name: "index_claims_on_invalidated_seq"
    t.index ["supersedes_claim_id"], name: "index_claims_on_supersedes_claim_id"
  end

  create_table "content_reviews", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "author_principal_id"
    t.datetime "created_at", null: false
    t.string "field", null: false
    t.datetime "lease_expires_at"
    t.uuid "leased_by_token_id"
    t.text "original_text", null: false
    t.string "reason"
    t.datetime "reviewed_at"
    t.uuid "reviewed_by_token_id"
    t.bigint "reviewed_by_user_id"
    t.string "status", default: "PENDING", null: false
    t.uuid "subject_id"
    t.bigint "subject_int_id"
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.index ["status", "created_at"], name: "index_content_reviews_on_status_and_created_at"
    t.index ["subject_type", "subject_id", "field"], name: "index_content_reviews_on_subject_type_and_subject_id_and_field"
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
    t.string "visibility", default: "PUBLIC", null: false
    t.index "((envelope ->> 'delegation_id'::text))", name: "index_contributions_on_envelope_delegation_id"
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
    t.string "home_url"
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
    t.bigint "user_id"
    t.index ["contributor_id"], name: "index_custodied_keys_on_contributor_id", unique: true
    t.index ["user_id"], name: "index_custodied_keys_on_user_id"
  end

  create_table "custom_affiliations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.string "group_slug", null: false
    t.string "label", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_custom_affiliations_on_slug", unique: true
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
    t.bigint "redacted_by_seq"
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
    t.bigint "redacted_by_seq"
    t.uuid "source_location_id", null: false
    t.text "statement"
    t.jsonb "structured_value"
    t.index ["contribution_id"], name: "index_evidence_items_on_contribution_id"
    t.index ["created_seq"], name: "index_evidence_items_on_created_seq"
    t.index ["independence_group_id"], name: "index_evidence_items_on_independence_group_id"
    t.index ["invalidated_seq"], name: "index_evidence_items_on_invalidated_seq"
    t.index ["source_location_id"], name: "index_evidence_items_on_source_location_id"
  end

  create_table "feature_requests", id: :uuid, default: nil, force: :cascade do |t|
    t.boolean "anonymous", default: false, null: false
    t.text "asked", null: false
    t.uuid "assistant_token_id", null: false
    t.string "context_tool"
    t.integer "count", default: 1, null: false
    t.datetime "created_at", null: false
    t.string "digest", null: false
    t.string "expected"
    t.string "last_error"
    t.text "needed", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_feature_requests_on_created_at"
    t.index ["digest"], name: "index_feature_requests_on_digest"
  end

  create_table "graph_snapshots", id: :uuid, default: nil, force: :cascade do |t|
    t.jsonb "checkpoint"
    t.timestamptz "created_at", null: false
    t.string "entry_hash", null: false
    t.string "label"
    t.bigint "seq", null: false
    t.index ["seq"], name: "index_graph_snapshots_on_seq", unique: true
  end

  create_table "independence_group_assignments", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "accepted_seq"
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.uuid "evidence_item_id", null: false
    t.uuid "independence_group_id", null: false
    t.bigint "invalidated_seq"
    t.bigint "redacted_by_seq"
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
    t.bigint "redacted_by_seq"
    t.index ["contribution_id"], name: "index_independence_groups_on_contribution_id"
    t.index ["created_seq"], name: "index_independence_groups_on_created_seq"
    t.index ["invalidated_seq"], name: "index_independence_groups_on_invalidated_seq"
  end

  create_table "inference_premises", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "accepted_seq"
    t.uuid "claim_id", null: false
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.uuid "inference_id", null: false
    t.bigint "invalidated_seq"
    t.string "polarity", null: false
    t.integer "position", default: 0, null: false
    t.index ["claim_id"], name: "index_inference_premises_on_claim_id"
    t.index ["inference_id", "position"], name: "index_inference_premises_on_inference_id_and_position"
  end

  create_table "inferences", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "accepted_seq"
    t.uuid "conclusion_claim_id", null: false
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.string "inference_type", null: false
    t.bigint "invalidated_seq"
    t.bigint "redacted_by_seq"
    t.string "rule"
    t.string "strength", null: false
    t.index ["conclusion_claim_id"], name: "index_inferences_on_conclusion_claim_id"
    t.index ["contribution_id"], name: "index_inferences_on_contribution_id"
  end

  create_table "investigation_receipts", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "assistant_token_id", null: false
    t.string "bundle_digest", null: false
    t.datetime "created_at", null: false
    t.jsonb "result", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["assistant_token_id", "bundle_digest"], name: "idx_on_assistant_token_id_bundle_digest_76f712cd1a", unique: true
  end

  create_table "investigations", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "assistant_token_id", null: false
    t.uuid "claim_ids", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.uuid "section_id"
    t.integer "snapshot_seq", null: false
    t.text "statement"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_investigations_on_created_at"
  end

  create_table "oauth_authorization_codes", id: :uuid, default: nil, force: :cascade do |t|
    t.boolean "anonymous", default: false, null: false
    t.string "code_challenge", null: false
    t.string "code_digest", null: false
    t.datetime "created_at", null: false
    t.timestamptz "expires_at", null: false
    t.uuid "oauth_client_id", null: false
    t.string "redirect_uri", null: false
    t.string "resource"
    t.string "scope"
    t.datetime "updated_at", null: false
    t.timestamptz "used_at"
    t.bigint "user_id"
    t.index ["code_digest"], name: "index_oauth_authorization_codes_on_code_digest", unique: true
    t.index ["oauth_client_id"], name: "index_oauth_authorization_codes_on_oauth_client_id"
  end

  create_table "oauth_clients", id: :uuid, default: nil, force: :cascade do |t|
    t.string "client_id", null: false
    t.string "client_secret_digest"
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "redirect_uris", default: [], null: false, array: true
    t.string "token_endpoint_auth_method", default: "none", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_oauth_clients_on_client_id", unique: true
  end

  create_table "oauth_tokens", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "assistant_token_id", null: false
    t.datetime "created_at", null: false
    t.timestamptz "expires_at"
    t.uuid "family_id", null: false
    t.string "kind", null: false
    t.uuid "oauth_client_id", null: false
    t.timestamptz "revoked_at"
    t.string "scope"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.timestamptz "used_at"
    t.index ["assistant_token_id"], name: "index_oauth_tokens_on_assistant_token_id"
    t.index ["family_id"], name: "index_oauth_tokens_on_family_id"
    t.index ["oauth_client_id"], name: "index_oauth_tokens_on_oauth_client_id"
    t.index ["token_digest"], name: "index_oauth_tokens_on_token_digest", unique: true
  end

  create_table "personal_assessments", id: :uuid, default: nil, force: :cascade do |t|
    t.jsonb "cites", default: [], null: false
    t.uuid "claim_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "lens", default: {}, null: false
    t.string "personal_probability"
    t.text "rationale"
    t.string "stance", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "visibility", default: "PRIVATE", null: false
    t.index ["claim_id", "stance"], name: "index_personal_assessments_on_claim_id_and_stance"
    t.index ["user_id", "claim_id"], name: "index_personal_assessments_on_user_id_and_claim_id", unique: true
  end

  create_table "quarantines", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.text "note"
    t.string "reason", null: false
    t.uuid "release_contribution_id"
    t.bigint "released_seq"
    t.uuid "target_id", null: false
    t.string "target_type", null: false
    t.index ["contribution_id"], name: "index_quarantines_on_contribution_id"
    t.index ["released_seq"], name: "index_quarantines_on_released_seq"
    t.index ["target_type", "target_id"], name: "index_quarantines_on_target_type_and_target_id"
  end

  create_table "reputation_events", id: :uuid, default: nil, force: :cascade do |t|
    t.decimal "alpha_delta", precision: 6, scale: 2, null: false
    t.uuid "audit_id", null: false
    t.decimal "beta_delta", precision: 6, scale: 2, null: false
    t.uuid "contribution_id", null: false
    t.uuid "contributor_id", null: false
    t.bigint "created_seq", null: false
    t.string "domain", null: false
    t.bigint "invalidated_seq"
    t.uuid "principal_contributor_id"
    t.string "task_type", null: false
    t.index ["audit_id"], name: "index_reputation_events_on_audit_id"
    t.index ["contributor_id", "task_type", "domain"], name: "idx_on_contributor_id_task_type_domain_f317753e89"
    t.index ["principal_contributor_id", "task_type", "domain"], name: "idx_on_principal_contributor_id_task_type_domain_8c73a2ddc9"
  end

  create_table "review_verdicts", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "assistant_token_id"
    t.datetime "created_at", null: false
    t.jsonb "detail", default: {}, null: false
    t.uuid "principal_contributor_id", null: false
    t.string "reason"
    t.string "subject_key", null: false
    t.string "subject_type", null: false
    t.string "verdict", null: false
    t.index ["subject_type", "subject_key", "principal_contributor_id"], name: "index_review_verdicts_one_per_principal", unique: true
  end

  create_table "scoring_models", id: :uuid, default: nil, force: :cascade do |t|
    t.string "code_hash", null: false
    t.jsonb "config", null: false
    t.string "config_hash", null: false
    t.uuid "contribution_id", null: false
    t.string "name", null: false
    t.string "release_signature", null: false
    t.bigint "released_seq", null: false
    t.string "semantic_version", null: false
    t.string "test_suite_result_hash"
    t.index ["contribution_id"], name: "index_scoring_models_on_contribution_id"
    t.index ["name", "semantic_version"], name: "index_scoring_models_on_name_and_semantic_version", unique: true
  end

  create_table "sections", id: :uuid, default: nil, force: :cascade do |t|
    t.bigint "accepted_seq"
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.integer "depth", default: 0, null: false
    t.string "heading", null: false
    t.bigint "invalidated_seq"
    t.uuid "location_id"
    t.uuid "parent_id"
    t.integer "position", default: 0, null: false
    t.bigint "redacted_by_seq"
    t.uuid "root_id", null: false
    t.uuid "source_id", null: false
    t.index ["contribution_id"], name: "index_sections_on_contribution_id"
    t.index ["root_id", "parent_id", "position"], name: "index_sections_on_root_id_and_parent_id_and_position"
    t.index ["source_id"], name: "index_sections_on_source_id"
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
    t.bigint "redacted_by_seq"
    t.uuid "source_id", null: false
    t.index ["contribution_id"], name: "index_source_locations_on_contribution_id"
    t.index ["created_seq"], name: "index_source_locations_on_created_seq"
    t.index ["invalidated_seq"], name: "index_source_locations_on_invalidated_seq"
    t.index ["source_id"], name: "index_source_locations_on_source_id"
  end

  create_table "source_retrievals", id: :uuid, default: nil, force: :cascade do |t|
    t.string "content_hash"
    t.integer "content_length"
    t.uuid "contribution_id", null: false
    t.bigint "created_seq", null: false
    t.jsonb "excerpts", default: [], null: false
    t.timestamptz "fetched_at", null: false
    t.string "final_url"
    t.bigint "invalidated_seq"
    t.string "media_type"
    t.string "outcome", null: false
    t.bigint "redacted_by_seq"
    t.bigint "source_created_seq", null: false
    t.uuid "source_id", null: false
    t.index ["contribution_id"], name: "index_source_retrievals_on_contribution_id"
    t.index ["source_id", "created_seq"], name: "index_source_retrievals_on_source_id_and_created_seq"
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
    t.bigint "redacted_by_seq"
    t.boolean "retrieval_pending", default: false, null: false
    t.timestamptz "retrieved_at"
    t.string "source_type", null: false
    t.string "title"
    t.index ["contribution_id"], name: "index_sources_on_contribution_id"
    t.index ["created_seq"], name: "index_sources_on_created_seq"
    t.index ["invalidated_seq"], name: "index_sources_on_invalidated_seq"
    t.index ["lineage_key"], name: "index_sources_on_lineage_key"
  end

  create_table "summaries", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "claim_id", null: false
    t.timestamptz "created_at", null: false
    t.string "generator", null: false
    t.string "input_hash", null: false
    t.uuid "scoring_model_id", null: false
    t.jsonb "sentences", null: false
    t.bigint "snapshot_seq", null: false
    t.string "summary_type", null: false
    t.index ["claim_id", "snapshot_seq", "scoring_model_id", "summary_type"], name: "index_summaries_on_claim_seq_model_type", unique: true
  end

  create_table "task_assignments", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "contributor_id", null: false
    t.datetime "created_at", null: false
    t.uuid "delegation_id"
    t.timestamptz "lease_expires_at", null: false
    t.uuid "principal_contributor_id", null: false
    t.uuid "result_contribution_id"
    t.string "status", default: "LEASED", null: false
    t.uuid "task_id", null: false
    t.datetime "updated_at", null: false
    t.index ["contributor_id", "created_at"], name: "index_task_assignments_on_contributor_id_and_created_at"
    t.index ["status", "lease_expires_at"], name: "index_task_assignments_on_status_and_lease_expires_at"
    t.index ["task_id", "contributor_id"], name: "index_task_assignments_active_per_contributor", unique: true, where: "((status)::text = ANY (ARRAY[('LEASED'::character varying)::text, ('SUBMITTED'::character varying)::text]))"
    t.index ["task_id", "principal_contributor_id"], name: "index_task_assignments_active_per_principal", unique: true, where: "((status)::text = ANY (ARRAY[('LEASED'::character varying)::text, ('SUBMITTED'::character varying)::text]))"
  end

  create_table "tasks", id: :uuid, default: nil, force: :cascade do |t|
    t.string "cancelled_reason"
    t.datetime "created_at", null: false
    t.uuid "created_by_contributor_id"
    t.string "domain", null: false
    t.bigint "issued_seq", null: false
    t.jsonb "packet", null: false
    t.string "packet_hash", null: false
    t.decimal "priority", precision: 10, scale: 4, default: "0.0", null: false
    t.integer "required_assignments", default: 1, null: false
    t.uuid "section_id"
    t.string "status", default: "OPEN", null: false
    t.uuid "target_id", null: false
    t.string "target_type", null: false
    t.string "task_type", null: false
    t.datetime "updated_at", null: false
    t.index ["packet_hash"], name: "index_tasks_on_packet_hash", unique: true
    t.index ["section_id"], name: "index_tasks_on_section_id"
    t.index ["status", "priority"], name: "index_tasks_on_status_and_priority", order: { priority: :desc }
    t.index ["target_type", "target_id"], name: "index_tasks_on_target_type_and_target_id"
    t.index ["task_type"], name: "index_tasks_on_task_type"
  end

  create_table "user_affiliations", force: :cascade do |t|
    t.string "affiliation", null: false
    t.datetime "created_at", null: false
    t.bigint "user_id", null: false
    t.index ["affiliation"], name: "index_user_affiliations_on_affiliation"
    t.index ["user_id", "affiliation"], name: "index_user_affiliations_on_user_id_and_affiliation", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "admin_granted_at"
    t.bigint "admin_granted_by_id"
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.boolean "moderator", default: false, null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "affiliation_requests", "users"
  add_foreign_key "bug_reports", "assistant_tokens"
  add_foreign_key "bug_reports", "users"
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
  add_foreign_key "feature_requests", "assistant_tokens"
  add_foreign_key "independence_group_assignments", "evidence_items"
  add_foreign_key "independence_group_assignments", "independence_groups"
  add_foreign_key "investigations", "assistant_tokens"
  add_foreign_key "oauth_authorization_codes", "oauth_clients"
  add_foreign_key "oauth_tokens", "assistant_tokens"
  add_foreign_key "oauth_tokens", "oauth_clients"
  add_foreign_key "personal_assessments", "users"
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
  add_foreign_key "task_assignments", "tasks"
  add_foreign_key "user_affiliations", "users"
end
