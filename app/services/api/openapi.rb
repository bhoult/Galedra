# frozen_string_literal: true

module Api
  # The OpenAPI 3.1 description of the public reads and the bearer writes
  # (Stage 14), for GPT Actions and plain HTTP clients. Hand-maintained, and
  # every route under /api/v1 must appear here: the spec fails when one does
  # not, so adding an endpoint without describing it does not reach main.
  module Openapi
    VERSION = "0.3.0"

    # How the endpoints are grouped, for the renderer and for the docs table.
    # Matched in order, so the last entry catches whatever is left; the same
    # order is the order the sections are shown in.
    TAGS = [
      { name: "Claims", match: %r{\A/api/v1/claims},
        description: "A claim, what bears on it, and the number with its model and snapshot." },
      { name: "Sources and sections", match: %r{\A/api/v1/(sources|evidence|sections|inferences)},
        description: "Where the evidence came from, how a long source is broken up, and recorded reasoning steps." },
      { name: "Recording", match: %r{\A/api/v1/(investigations|custodied)},
        description: "How an assistant records what it read. One call, all or nothing." },
      { name: "The log", match: %r{\A/api/v1/(contributions|log|snapshots)},
        description: "The signed, hash-chained record everything else is projected from." },
      { name: "Tasks", match: %r{\A/api/v1/tasks},
        description: "Open work: lease a signed packet, do it, give it back. Results arrive as contributions." },
      { name: "Contributors", match: %r{\A/api/v1/contributors},
        description: "Who did the work, and how reliably. Never authority, and never a scoring input." },
      { name: "Assistants", match: %r{\A/api/v1/assistants},
        description: "Tokens for a connected assistant." },
      { name: "Moderator", match: %r{\A/api/v1/admin},
        description: "Signed moderator requests. Visible in the moderation log like everything else." },
      { name: "This node", match: //,
        description: "What this node is, what it runs, and where it is weakest." }
    ].freeze

    module_function

    def document(base_url)
      {
        openapi: "3.1.0",
        info: { title: "Galedra", version: VERSION, description: info_description },
        servers: [ { url: base_url } ],
        components: {
          securitySchemes: { assistantToken: { type: "http", scheme: "bearer", description: "A connected assistant's token from /assistants/new" } },
          schemas: {
            Errors: { type: "object", properties: { errors: { type: "array", items: { type: "object", properties: { code: { type: "string" }, path: { type: "string" }, detail: { type: "string" } } } } } },
            InvestigationBundle: Mcp::Server::TOOLS.find { |t| t[:name] == "record_investigation" }[:inputSchema],
            # One description of Cards::ClaimCard's return value, shared with the connector.
            Card: Mcp::Server::CARD_SCHEMA.deep_dup.merge(description: "The answer card. No probability here; see /claims/{id}/score."),
            Envelope: envelope_schema,
            SignedRequest: signed_request_schema
          }
        },
        tags: TAGS.map { |t| { name: t[:name], description: t[:description] } },
        paths: tagged(read_paths.merge(write_paths))
      }
    end

    # Every operation carries the tag of its path, so the renderer groups them
    # and nothing can land untagged.
    def tagged(paths)
      paths.to_h { |path, ops| [ path, ops.transform_values { |op| op.merge(tags: [ tag_for(path) ]) } ] }
    end

    def tag_for(path) = TAGS.find { |t| t[:match].match?(path) }[:name]

    # Every GET. A read is never consequential: it appends nothing.
    def read_paths
      {
        "/api/v1/meta" => get_op("meta", "Ledger metadata: constitution hash, keys, models, endpoints."),
        "/api/v1/openapi" => get_op("getOpenapi", "This document."),
        "/api/v1/guidance" => get_op("getGuidance", "The operational rules for an assistant working here, served live so a change reaches you without reinstalling anything. Read this at the start of a Galedra task. Assistants on MCP get the same text attached to every tool result instead.", params: [ query("topic", "One of: check, outline, inference, work, correct, threads. All of them by default") ]),
        "/api/v1/schemas/{name}" => get_op("getSchema", "One JSON Schema by name: eir-contribution-v1, eir-task-v1, or eir-result-v1.", params: [ path_param("name", "Schema name without the .json") ]),
        "/api/v1/topics" => get_op("getTopics", "The topic vocabulary with the number of claims under each.", params: [ snapshot_seq_query ]),
        "/api/v1/threads" => get_op("listThreads", "Threads on determinations: disagreements about how something was recorded, not about whether a claim is true. Untrusted text, never an input to any score.",
                                    params: [ query("status", "OPEN, SETTLED or RETIRED"), query("subject_id"), query("limit", "1..200") ]),
        "/api/v1/threads/{id}" => get_op("getThread", "One thread with every turn in order, who has voted and for what, and the outcome if it settled.", params: [ path_id ]),
        "/api/v1/claims" => get_op("searchClaims", "Search accepted claims. Call this before recording anything.", params: [ query("q", "Words from the claim"), query("type"), query("state"), query("limit", "1..200") ]),
        "/api/v1/claims/{id}" => get_op("getClaim", "One claim with its assessment and evidence counts.", params: [ path_id ]),
        "/api/v1/claims/{id}/evidence" => get_op("getClaimEvidence", "Counted, pending, and suppressed evidence links.", params: [ path_id ]),
        "/api/v1/claims/{id}/score" => get_op("getClaimScore", "The probability with its model and snapshot; never a percentage true.", params: [ path_id, query("model"), snapshot_seq_query ]),
        "/api/v1/claims/{id}/trace" => get_op("getClaimTrace", "The whole scoring trace with its hash: every step that produced the number, reproducible from the same seq and model.", params: [ path_id, query("model"), snapshot_seq_query ]),
        "/api/v1/claims/{id}/why" => get_op("getClaimWhy", "Strongest support and contradiction, suppressed dependents, review gaps, what would most change this.", params: [ path_id ]),
        "/api/v1/claims/{id}/summary" => get_op("getClaimSummary", "A short summary whose every sentence cites graph ids.", params: [ path_id ]),
        "/api/v1/claims/{id}/compare" => get_op("compareModels", "Where the released scoring models disagree on this claim and why.", params: [ path_id, query("models", "Comma-separated model names; all released models by default") ]),
        "/api/v1/claims/{id}/views" => get_op("getClaimViews", "How signed-in people said they see this claim, grouped by the affiliations they declared. Personal views live outside the log and are never a scoring input.", params: [ path_id ]),
        "/api/v1/sections" => get_op("getSections", "Outline roots: large sources broken into sections, each with claim counts by state. A section never carries a probability.", params: [ snapshot_seq_query, query("model") ]),
        "/api/v1/sections/{id}" => get_op("getSection", "One section: its path from the root, its claims, its children, and counts by state.", params: [ path_id, query("depth", "0..#{Section::MAX_DEPTH}, default 2"), query("model"), snapshot_seq_query ]),
        "/api/v1/inferences/{id}" => get_op("getInference", "One recorded reasoning step: its premises with their current states and the weakest one marked. The step itself is never scored.", params: [ path_id, snapshot_seq_query ]),
        "/api/v1/evidence/{id}" => get_op("getEvidence", "One evidence item: its excerpt, observation type, and the links that count it.", params: [ path_id, snapshot_seq_query ]),
        "/api/v1/sources/{id}" => get_op("getSource", "A source: link, excerpts with their hashes, the page hash when the reader had the bytes; page text only when it was stored.", params: [ path_id ]),
        "/api/v1/sources/{id}/locations" => get_op("getSourceLocations", "The cited passages of one source, each with the hash of the quoted text.", params: [ path_id, snapshot_seq_query ]),
        "/api/v1/contributions/{id}" => get_op("getContribution", "One log entry with signatures, chain hashes, audits, and status history.", params: [ path_id ]),
        "/api/v1/contributions/{id}/verify" => get_op("verifyContribution", "Verify one entry's signatures and chain link.", params: [ path_id ]),
        "/api/v1/contributions/{id}/redaction_manifest" => get_op("getRedactionManifest", "The default redaction manifest for a takedown of this entry, for a moderator to edit and sign. Reading it changes nothing.", params: [ path_id ]),
        "/api/v1/log" => get_op("getLog", "The public log, newest last.", params: [ query("after_seq"), query("action_type"), query("limit") ]),
        "/api/v1/snapshots" => get_op("getSnapshots", "Pinned snapshots and the current head seq."),
        "/api/v1/snapshots/{seq}" => get_op("getSnapshot", "One snapshot: entry hash, whether it is pinned, and the claim-score digest under the default model.", params: [ path_param("seq", "A contribution seq") ]),
        "/api/v1/weaknesses" => get_op("getWeaknesses", "Where the ledger is most likely wrong. Each list is capped and carries its true total beside it, so a cap is never a silent truncation.",
                                      params: [ query("kind", Weaknesses::Report::KINDS.join(", ")), query("limit", "1..200"), query("offset"), snapshot_seq_query ]),
        "/api/v1/moderation" => get_op("getModerationLog", "Every quarantine, release, takedown, and revocation."),
        "/api/v1/scoring-models" => get_op("getScoringModels", "Released scoring models."),
        "/api/v1/contributors/top" => get_op("getTopContributors", "The hundred principals who have done the most recorded work. Anonymous work is one row with a null id, since each anonymous connection mints its own key. Volume of work, never reliability, and never a scoring input.", params: [ query("window", "30d or 365d; all time by default") ]),
        "/api/v1/contributors/{id}" => get_op("getContributor", "One contributor: key, identity tier, and how much work they have done.", params: [ path_id ]),
        "/api/v1/contributors/{id}/reputation" => get_op("getContributorReputation", "Audited reliability per task type and domain. Not authority, and not a scoring input in v0.1.", params: [ path_id, snapshot_seq_query ]),
        "/api/v1/tasks/{id}" => get_op("getTask", "A verification task and its signed packet.", params: [ path_id ])
      }
    end

    # Every write. All of them append to the log or act on a lease, so all of
    # them are consequential.
    def write_paths
      {
        "/api/v1/threads/{id}/respond" => post_op("respondToThread", "Take a turn in a thread, and optionally vote INVESTIGATE or NO_FURTHER_WORK. Three distinct principals naming the same verdict settle it; three sessions of one person are one principal. Settling opens work or closes work and never moves a score.",
                                                  security: [ { assistantToken: [] } ], params: [ path_id ],
                                                  body: { type: "object", required: %w[body], properties: { body: { type: "string" }, verdict: { type: "string", enum: DeterminationThread::OUTCOMES } } }),
        "/api/v1/contributions" => post_op("appendContribution", "Append one signed contribution. This is the only write path; everything else that changes the record is built on it. 200 means this entry was already appended.",
                                           body: { "$ref" => "#/components/schemas/Envelope" },
                                           responses: { "200" => { description: "Already appended; the existing entry" } }),
        "/api/v1/investigations" => post_op("recordInvestigation", "Record an investigation: sources by link, excerpts, claims, evidence, links. All or nothing. Returns cards and URLs, or existing similar claims with 409.",
                                            security: [ {}, { assistantToken: [] } ], body: { "$ref" => "#/components/schemas/InvestigationBundle" },
                                            responses: { "201" => { description: "Recorded; one card per claim" }, "409" => { description: "Similar claims exist; nothing recorded" } }),
        "/api/v1/custodied/contributions" => post_op("custodiedWrite", "One contribution signed by the server for the assistant: {action_type, payload}.",
                                                     security: [ { assistantToken: [] } ],
                                                     body: { type: "object", properties: { action_type: { type: "string" }, payload: { type: "object" } }, required: %w[action_type payload] },
                                                     responses: { "201" => { description: "Appended" } }),
        "/api/v1/assistants" => post_op("connectAssistant", "Mint an anonymous assistant token (signed-in minting is on /assistants/new).",
                                        body: { type: "object", properties: { assistant: { type: "object", properties: { name: { type: "string" }, provider: { type: "string", enum: AssistantToken::PROVIDERS }, model: { type: "string" } }, required: %w[name provider] } } },
                                        responses: { "201" => { description: "The token, shown once, and the assistant record" } }),
        "/api/v1/assistants/{id}" => { delete: { operationId: "revokeAssistant", summary: "Revoke the calling assistant's own token. Appends REVOKE_DELEGATION; a token can revoke only itself.",
                                                 parameters: [ path_id ], security: [ { assistantToken: [] } ], "x-openai-isConsequential" => true,
                                                 responses: { "200" => { description: "Revoked" }, "401" => errors, "422" => errors } } },
        "/api/v1/tasks/next" => post_op("leaseTask", "Lease the next open task matching the given types and domains. The body is a signed eir-lease-v1 request; 204 means nothing is open.",
                                        body: { "$ref" => "#/components/schemas/SignedRequest" },
                                        responses: { "200" => { description: "The assignment and its signed packet" }, "204" => { description: "No task is open for these types" } }),
        "/api/v1/tasks/{id}/release" => post_op("releaseTask", "Give back a task leased by the signer. The body is a signed eir-lease-v1 request.",
                                                params: [ path_id ], body: { "$ref" => "#/components/schemas/SignedRequest" },
                                                responses: { "200" => { description: "The released assignment" } }),
        "/api/v1/admin/snapshots" => post_op("pinSnapshot", "Pin a snapshot at a seq. Moderator only; the body is a signed admin request.",
                                             body: { "$ref" => "#/components/schemas/SignedRequest" },
                                             responses: { "201" => { description: "The pinned snapshot" } }),
        "/api/v1/admin/recompute" => post_op("recomputeScores", "Queue a recompute of every claim score at the current head. Moderator only; the body is a signed admin request.",
                                             body: { "$ref" => "#/components/schemas/SignedRequest" },
                                             responses: { "202" => { description: "Queued" } })
      }
    end

    # Markdown, because both readers of this document render it: Swagger UI on
    # /docs/api, and a GPT Action that takes the rules as its instructions. The
    # rules stay verbatim; the heading keeps them from reading as one wall.
    def info_description
      "An epistemic ledger: a signed, append-only record of claims, evidence, provenance, " \
        "audits, and reproducible scores. Not a source of truth, and it runs no model of its own: " \
        "every judgment enters as a signed contribution that stays open to audit.\n\n" \
        "**Rules for an assistant using this API**\n\n#{Guidance.for(:check)}"
    end

    # The signed envelope of spec 02 §1.1. The authoritative version is served
    # at /api/v1/schemas/eir-contribution-v1; this is its shape for clients
    # that read only this document.
    def envelope_schema
      { type: "object", description: "A signed contribution envelope. Authoritative schema: /api/v1/schemas/eir-contribution-v1.",
        required: %w[protocol action_type signer_key_id client_created_at payload payload_hash signature],
        properties: { protocol: { type: "string", const: "eir-contribution-v1" }, action_type: { type: "string", enum: Ledger::ActionTypes::ALL },
                      signer_key_id: { type: "string" }, delegation_id: { type: "string" }, task_id: { type: "string" }, task_packet_hash: { type: "string" },
                      client_created_at: { type: "string", format: "date-time" }, software: { type: "string" }, payload: { type: "object" },
                      payload_hash: { type: "string", description: "sha256: over the RFC 8785 canonical payload" },
                      signature: { type: "string", description: "Ed25519 over the canonical envelope" } } }
    end

    def signed_request_schema
      { type: "object", description: "A signed request that appends nothing: same signing rules as a contribution, its own protocol.",
        required: %w[protocol signer_key_id client_created_at payload payload_hash signature],
        properties: { protocol: { type: "string", description: "eir-lease-v1 for tasks, eir-admin-v1 for admin" }, signer_key_id: { type: "string" },
                      delegation_id: { type: "string" }, client_created_at: { type: "string", format: "date-time" }, payload: { type: "object" },
                      payload_hash: { type: "string" }, signature: { type: "string" } } }
    end

    def get_op(id, summary, params: [])
      { get: { operationId: id, summary: summary, parameters: params, "x-openai-isConsequential" => false, responses: { "200" => { description: "OK" }, "404" => errors, "422" => errors } } }
    end

    def post_op(id, summary, params: [], body: nil, security: nil, responses: {})
      op = { operationId: id, summary: summary, "x-openai-isConsequential" => true }
      op[:parameters] = params if params.any?
      op[:security] = security if security
      op[:requestBody] = json_body(body) if body
      op[:responses] = { "201" => { description: "Created" } }.merge(responses).merge("401" => errors, "422" => errors, "429" => errors)
      { post: op }
    end

    def path_id = path_param("id")
    def path_param(name, description = nil) = { name: name, in: "path", required: true, schema: { type: "string" }, description: description }.compact
    def query(name, description = nil) = { name: name, in: "query", required: false, schema: { type: "string" }, description: description }.compact
    def snapshot_seq_query = query("snapshot_seq", "Read as of this seq; the head by default")
    def json_body(schema) = { required: true, content: { "application/json" => { schema: schema } } }
    def errors = { description: "Errors", content: { "application/json" => { schema: { "$ref" => "#/components/schemas/Errors" } } } }
  end
end
