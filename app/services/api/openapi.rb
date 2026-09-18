# frozen_string_literal: true

module Api
  # The OpenAPI 3.1 description of the public reads and the bearer writes
  # (Stage 14), for GPT Actions and plain HTTP clients. Hand-maintained;
  # the spec checks every listed path responds.
  module Openapi
    VERSION = "0.2.0"

    module_function

    def document(base_url)
      {
        openapi: "3.1.0",
        info: { title: "Galedra", version: VERSION,
                description: "An epistemic ledger: a signed, append-only record of claims, evidence, provenance, audits, and reproducible scores. Not a source of truth. #{Mcp::Server::RULES}" },
        servers: [ { url: base_url } ],
        components: {
          securitySchemes: { assistantToken: { type: "http", scheme: "bearer", description: "A connected assistant's token from /assistants/new" } },
          schemas: {
            Errors: { type: "object", properties: { errors: { type: "array", items: { type: "object", properties: { code: { type: "string" }, path: { type: "string" }, detail: { type: "string" } } } } } },
            InvestigationBundle: Mcp::Server::TOOLS.find { |t| t[:name] == "record_investigation" }[:inputSchema],
            Card: { type: "object", description: "The answer card. No probability here; see /claims/{id}/score.",
                    properties: { headline: { type: "string" }, plain: { type: "object", properties: { headline: { type: "string" }, say_instead: { type: [ "string", "null" ] } } },
                                  review_checks: { type: "string" }, labels: { type: "array", items: { type: "string" } }, model: { type: "string" }, snapshot_seq: { type: "integer" } } }
          }
        },
        paths: {
          "/api/v1/meta" => get_op("meta", "Ledger metadata: constitution hash, keys, models, endpoints."),
          "/api/v1/claims" => get_op("searchClaims", "Search accepted claims. Call this before recording anything.", params: [ query("q", "Words from the claim"), query("type"), query("state"), query("limit", "1..200") ]),
          "/api/v1/claims/{id}" => get_op("getClaim", "One claim with its assessment and evidence counts.", params: [ path_id ]),
          "/api/v1/claims/{id}/evidence" => get_op("getClaimEvidence", "Counted, pending, and suppressed evidence links.", params: [ path_id ]),
          "/api/v1/claims/{id}/score" => get_op("getClaimScore", "The probability with its model and snapshot; never a percentage true.", params: [ path_id, query("model"), query("snapshot_seq") ]),
          "/api/v1/claims/{id}/why" => get_op("getClaimWhy", "Strongest support and contradiction, suppressed dependents, review gaps, what would most change this.", params: [ path_id ]),
          "/api/v1/claims/{id}/summary" => get_op("getClaimSummary", "A short summary whose every sentence cites graph ids.", params: [ path_id ]),
          "/api/v1/claims/{id}/compare" => get_op("compareModels", "Where the released scoring models disagree on this claim and why.", params: [ path_id ]),
          "/api/v1/sources/{id}" => get_op("getSource", "A source: link, excerpts with their hashes, the page hash when the reader had the bytes; page text only when it was stored.", params: [ path_id ]),
          "/api/v1/contributions/{id}" => get_op("getContribution", "One log entry with signatures, chain hashes, audits, and status history.", params: [ path_id ]),
          "/api/v1/contributions/{id}/verify" => get_op("verifyContribution", "Verify one entry's signatures and chain link.", params: [ path_id ]),
          "/api/v1/log" => get_op("getLog", "The public log, newest last.", params: [ query("after_seq"), query("action_type"), query("limit") ]),
          "/api/v1/weaknesses" => get_op("getWeaknesses", "Where the ledger is most likely wrong."),
          "/api/v1/moderation" => get_op("getModerationLog", "Every quarantine, release, takedown, and revocation."),
          "/api/v1/scoring-models" => get_op("getScoringModels", "Released scoring models."),
          "/api/v1/tasks/{id}" => get_op("getTask", "A verification task and its signed packet.", params: [ path_id ]),
          "/api/v1/assistants" => { post: { operationId: "connectAssistant", summary: "Mint an anonymous assistant token (signed-in minting is on /assistants/new).",
                                            requestBody: json_body({ type: "object", properties: { assistant: { type: "object", properties: { name: { type: "string" }, provider: { type: "string", enum: AssistantToken::PROVIDERS }, model: { type: "string" } }, required: %w[name provider] } } }),
                                            responses: { "201" => { description: "The token, shown once, and the assistant record" }, "422" => errors, "429" => errors } } },
          "/api/v1/investigations" => { post: { operationId: "recordInvestigation", summary: "Record an investigation: sources by link, excerpts, claims, evidence, links. All or nothing. Returns cards and URLs, or existing similar claims with 409.",
                                                security: [ {}, { assistantToken: [] } ], requestBody: json_body({ "$ref" => "#/components/schemas/InvestigationBundle" }),
                                                responses: { "201" => { description: "Recorded; one card per claim" }, "409" => { description: "Similar claims exist; nothing recorded" }, "401" => errors, "422" => errors, "429" => errors } } },
          "/api/v1/custodied/contributions" => { post: { operationId: "custodiedWrite", summary: "One contribution signed by the server for the assistant: {action_type, payload}.",
                                                         security: [ { assistantToken: [] } ], requestBody: json_body({ type: "object", properties: { action_type: { type: "string" }, payload: { type: "object" } }, required: %w[action_type payload] }),
                                                         responses: { "201" => { description: "Appended" }, "401" => errors, "422" => errors, "429" => errors } } }
        }
      }
    end

    def get_op(id, summary, params: [])
      { get: { operationId: id, summary: summary, parameters: params, "x-openai-isConsequential" => false, responses: { "200" => { description: "OK" }, "404" => errors, "422" => errors } } }
    end

    def path_id = { name: "id", in: "path", required: true, schema: { type: "string" } }
    def query(name, description = nil) = { name: name, in: "query", required: false, schema: { type: "string" }, description: description }.compact
    def json_body(schema) = { required: true, content: { "application/json" => { schema: schema } } }
    def errors = { description: "Errors", content: { "application/json" => { schema: { "$ref" => "#/components/schemas/Errors" } } } }
  end
end
