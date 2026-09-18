# frozen_string_literal: true

module Mcp
  # A small Model Context Protocol server (Stage 14): JSON-RPC 2.0 over
  # streamable HTTP at POST /mcp. Reads are open, like the rest of the public
  # API; the two writing tools need a connected assistant's bearer token.
  # Tool descriptions carry the working rules, not just the schemas.
  class Server
    PROTOCOL_VERSION = "2025-06-18"
    VERSION = "0.2.0"
    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    TOKEN_REQUIRED = -32001

    RULES = "Search Galedra before recording. Do your own reading: Galedra never fetches URLs. " \
            "Quote the exact passage with its link and a sha256 of what you read. One assertion per claim, typed. " \
            "Your own reasoning is never evidence; only quoted passages are. Look for what would count against a claim before recording it. " \
            "Never record claims about identifiable private individuals. Report Galedra's plain headline and its say_instead sentence verbatim, never a paraphrase of your own, plus the link, and say the result is provisional until audited. When the result carries attribution.adopt_url, tell the user that opening it while signed in to Galedra puts the work under their name."

    CARD_SCHEMA = { type: "object", description: "The answer card; no probability here.",
                    properties: { headline: { type: "string" }, plain: { type: "object", properties: { headline: { type: "string" }, say_instead: { type: [ "string", "null" ] } } },
                                  review_checks: { type: "string" }, labels: { type: "array", items: { type: "string" } }, model: { type: "string" }, snapshot_seq: { type: "integer" } } }.freeze
    RECORD_OUTPUT_SCHEMA = { type: "object", properties: {
      recorded: { type: "boolean" }, contributions: { type: "integer" }, tasks_opened: { type: "integer" }, snapshot_seq: { type: "integer" },
      claims: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, id: { type: "string" }, created: { type: "boolean" }, url: { type: "string" }, card: CARD_SCHEMA } } },
      existing: { type: "object", description: "Similar accepted claims per handle, when nothing was recorded" }, hint: { type: "string" }
    } }.freeze

    TOOLS = [
      { name: "search_claims", annotations: { readOnlyHint: true, openWorldHint: false }, description: "Search accepted claims by words. Always call this first: if the claim is already recorded, report its card and URL instead of recording a twin.",
        inputSchema: { type: "object", properties: { query: { type: "string", description: "Words from the claim" }, limit: { type: "integer", minimum: 1, maximum: 50, default: 10 } }, required: [ "query" ] },
        outputSchema: { type: "object", properties: { query: { type: "string" }, snapshot_seq: { type: "integer" }, claims: { type: "array", items: { type: "object", properties: { id: { type: "string" }, text: { type: "string" }, type: { type: "string" }, headline: { type: "string" }, plain_headline: { type: "string" }, url: { type: "string" } } } } } } },
      { name: "get_claim", annotations: { readOnlyHint: true, openWorldHint: false }, description: "The answer card for one claim: a plain headline, what to say instead when the evidence supports it, review checks, labels, counted evidence for and against, and the URL. No probability here; use explain with calculation: true for the number.",
        inputSchema: { type: "object", properties: { claim_id: { type: "string" } }, required: [ "claim_id" ] },
        outputSchema: { type: "object", properties: { id: { type: "string" }, text: { type: "string" }, type: { type: "string" }, url: { type: "string" }, card: CARD_SCHEMA, provisional_note: { type: "string" } } } },
      { name: "record_investigation", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false }, description: "Record what you found, all at once: sources by link and content hash, quoted excerpts, atomic typed claims, evidence statements, and links (SUPPORT, CONTRADICT, QUALIFY, NEUTRAL) with interpretive steps. No token is needed: without one the work is recorded under an anonymous key; a connected assistant token attributes it to the user. If similar accepted claims exist the call returns them under existing and records nothing; resubmit with attach_to on those claims, or on_duplicate: create. " + RULES,
        inputSchema: { type: "object", properties: {
          sources: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, type: { type: "string", enum: Source::TYPES }, title: { type: "string" }, url: { type: "string" }, content_hash: { type: "string", description: "sha256:<hex> of the bytes you read" }, retrieved_at: { type: "string", description: "RFC 3339" }, publisher: { type: "string" }, publication_date: { type: "string" } }, required: %w[handle type title url content_hash retrieved_at] } },
          excerpts: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, source: { type: "string" }, kind: { type: "string", enum: %w[QUOTE TRANSCRIPTION] }, text: { type: "string" } }, required: %w[handle source text] } },
          claims: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, text: { type: "string" }, type: { type: "string", enum: Claim::TYPES }, attach_to: { type: "string", description: "An existing claim id instead of text and type" } }, required: [ "handle" ] } },
          evidence: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, excerpt: { type: "string" }, statement: { type: "string" }, observation_type: { type: "string", enum: EvidenceItem::OBSERVATION_TYPES } }, required: %w[handle excerpt statement] } },
          links: { type: "array", items: { type: "object", properties: { evidence: { type: "string" }, claim: { type: "string" }, direction: { type: "string", enum: EvidenceClaimLink::DIRECTIONS }, strength: { type: "string", enum: EvidenceClaimLink::STRENGTHS }, steps: { type: "integer", minimum: 0, maximum: EvidenceClaimLink::MAX_STEPS }, note: { type: "string" } }, required: %w[evidence claim direction] } },
          groups: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, type: { type: "string", enum: IndependenceGroup::TYPES }, members: { type: "array", items: { type: "string" } } }, required: %w[handle members] } },
          on_duplicate: { type: "string", enum: %w[ask create], default: "ask" }
        }, required: [ "claims" ] },
        outputSchema: RECORD_OUTPUT_SCHEMA },
      { name: "add_evidence", annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false }, description: "Attach one quoted passage to an existing claim as evidence for, against, or qualifying it. No token needed; anonymous without one. " + RULES,
        inputSchema: { type: "object", properties: { claim_id: { type: "string" }, source: { type: "object", properties: { type: { type: "string", enum: Source::TYPES }, title: { type: "string" }, url: { type: "string" }, content_hash: { type: "string" }, retrieved_at: { type: "string" }, publisher: { type: "string" } }, required: %w[type title url content_hash retrieved_at] }, excerpt: { type: "string" }, excerpt_kind: { type: "string", enum: %w[QUOTE TRANSCRIPTION], default: "QUOTE" }, statement: { type: "string" }, direction: { type: "string", enum: EvidenceClaimLink::DIRECTIONS }, strength: { type: "string", enum: EvidenceClaimLink::STRENGTHS, default: "DIRECT" }, steps: { type: "integer", default: 0 }, note: { type: "string" } }, required: %w[claim_id source excerpt statement direction] },
        outputSchema: RECORD_OUTPUT_SCHEMA },
      { name: "explain", annotations: { readOnlyHint: true, openWorldHint: false }, description: "Why a claim stands where it does: strongest counted support and contradiction, suppressed dependents, review gaps, and what would most change it. With calculation: true, also the probability, always stated with its model and snapshot; never present it as a percentage true.",
        inputSchema: { type: "object", properties: { claim_id: { type: "string" }, calculation: { type: "boolean", default: false } }, required: [ "claim_id" ] },
        outputSchema: { type: "object", properties: { url: { type: "string" }, why: { type: "object" }, calculation: { type: "object", properties: { assessment_state: { type: "string" }, probability: { type: [ "string", "null" ] }, model: { type: "string" }, snapshot_seq: { type: "integer" }, stated_as: { type: [ "string", "null" ] } } } } } },
      { name: "share_card", annotations: { readOnlyHint: true, openWorldHint: false }, description: "A link and image for pasting into a social post: the plain headline, what to say instead, and the claim URL. The card never shows a number.",
        inputSchema: { type: "object", properties: { claim_id: { type: "string" } }, required: [ "claim_id" ] },
        outputSchema: { type: "object", properties: { url: { type: "string" }, card_url: { type: "string" }, image_url: { type: "string" }, headline: { type: "string" }, say_instead: { type: [ "string", "null" ] }, text: { type: "string" } } } },
      # OpenAI's read-and-fetch connector shape (ChatGPT search and deep research): a
      # `search` returning ids, titles, and URLs, and a `fetch` returning one document.
      { name: "search", annotations: { readOnlyHint: true, openWorldHint: false }, description: "Search Galedra's accepted claims. Returns ids, titles (the claim text with its plain headline), and URLs. Use fetch on an id for the full card, evidence, and why.",
        inputSchema: { type: "object", properties: { query: { type: "string" } }, required: [ "query" ] },
        outputSchema: { type: "object", properties: { results: { type: "array", items: { type: "object", properties: { id: { type: "string" }, title: { type: "string" }, url: { type: "string" } } } } } } },
      { name: "fetch", annotations: { readOnlyHint: true, openWorldHint: false }, description: "Fetch one Galedra claim by id: the answer card in plain words, what to say instead, review checks, the strongest evidence for and against, and the URL. Provisional until audited; never a percentage true.",
        inputSchema: { type: "object", properties: { id: { type: "string" } }, required: [ "id" ] },
        outputSchema: { type: "object", properties: { id: { type: "string" }, title: { type: "string" }, text: { type: "string" }, url: { type: "string" }, metadata: { type: "object" } } } }
    ].freeze

    def initialize(token:, base_url:)
      @token = token
      @base_url = base_url
    end

    # Returns [http_status, body_or_nil].
    def handle(message)
      return [ 400, error(nil, INVALID_REQUEST, "expected a JSON-RPC 2.0 request object") ] unless message.is_a?(Hash) && message["jsonrpc"] == "2.0"

      id = message["id"]
      method = message["method"].to_s
      params = message["params"].is_a?(Hash) ? message["params"] : {}
      return [ 202, nil ] if method.start_with?("notifications/")

      result = case method
      when "initialize" then initialize_result
      when "ping" then {}
      when "tools/list" then { tools: TOOLS }
      when "tools/call" then call_tool(params)
      else return [ 200, error(id, METHOD_NOT_FOUND, "unknown method #{method}") ]
      end
      [ 200, { jsonrpc: "2.0", id: id, result: result } ]
    rescue Ledger::Rejected => e
      [ 200, tool_error(id, e.errors) ]
    rescue Assistants::CapReached => e
      [ 200, tool_error(id, [ { code: "DAILY_CAP", path: "$", detail: e.message } ]) ]
    rescue ArgumentError => e
      [ 200, error(id, INVALID_PARAMS, e.message) ]
    end

    def initialize_result
      { protocolVersion: PROTOCOL_VERSION, capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "galedra", version: VERSION },
        instructions: "Galedra is an epistemic ledger: a signed record of claims, evidence, and reasons, not a source of truth. #{RULES}" }
    end

    def call_tool(params)
      name = params["name"].to_s
      args = params["arguments"].is_a?(Hash) ? params["arguments"] : {}
      raise ArgumentError, "unknown tool #{name}" unless TOOLS.any? { |t| t[:name] == name }

      data = send(:"tool_#{name}", args)
      { content: [ { type: "text", text: JSON.pretty_generate(data) } ], structuredContent: data, isError: false }
    end

    def tool_search_claims(args)
      query = args["query"].to_s.strip
      raise ArgumentError, "query is required" if query.empty?

      seq = Contribution.maximum(:seq) || 0
      model = Scoring::Registry.default_model
      scope = Claim.counted_at(seq).where.not(id: Governance::Quarantines.quarantined_claim_ids)
                   .where("to_tsvector('english', canonical_text) @@ plainto_tsquery('english', ?)", query)
                   .order(created_seq: :desc).limit(args.fetch("limit", 10).to_i.clamp(1, 50))
      claims = scope.to_a
      claims = Claims::Duplicates.candidates(query, limit: 10).to_a if claims.empty?
      { query: query, snapshot_seq: seq, claims: claims.map { |c| brief(c, seq, model) } }
    end

    def tool_get_claim(args)
      claim = find_claim(args)
      seq = Contribution.maximum(:seq)
      model = Scoring::Registry.default_model
      card = Cards::ClaimCard.call(claim, seq, model)
      evidence = Graph::Presenter.claim_evidence(claim, seq) if Graph::Presenter.respond_to?(:claim_evidence)
      { id: claim.id, text: claim.canonical_text, type: claim.claim_type, url: url_for(claim), card: card,
        evidence: evidence, provisional_note: "Everything here stays open to audit; treat it as provisional." }
    end

    def tool_record_investigation(args)
      require_token!
      Investigations::Record.call(@token, args, base_url: @base_url)
    end

    def tool_add_evidence(args)
      require_token!
      claim = find_claim(args)
      source = args.fetch("source", {})
      bundle = {
        "sources" => [ source.merge("handle" => "s") ],
        "excerpts" => [ { "handle" => "x", "source" => "s", "kind" => args.fetch("excerpt_kind", "QUOTE"), "text" => args["excerpt"] } ],
        "claims" => [ { "handle" => "c", "attach_to" => claim.id } ],
        "evidence" => [ { "handle" => "e", "excerpt" => "x", "statement" => args["statement"], "observation_type" => args.fetch("observation_type", "DIRECT_TEXT") } ],
        "links" => [ { "evidence" => "e", "claim" => "c", "direction" => args["direction"], "strength" => args.fetch("strength", "DIRECT"), "steps" => args.fetch("steps", 0), "note" => args["note"] }.compact ]
      }
      Investigations::Record.call(@token, bundle, base_url: @base_url)
    end

    def tool_explain(args)
      claim = find_claim(args)
      seq = Contribution.maximum(:seq)
      model = Scoring::Registry.default_model
      why = Cards::Why.call(claim, seq, model)
      out = { url: url_for(claim), why: why }
      if args["calculation"]
        result = Scoring::Score.call(claim, seq, model)
        out[:calculation] = { assessment_state: result.assessment_state, probability: result.probability, model: model.full_name, snapshot_seq: seq,
                              stated_as: result.probability && "#{result.probability} under #{model.full_name} at snapshot #{seq}",
                              review_checklist: result.review_checklist, stability: result.stability, note: "Model-conditional and reproducible, not objective; never a percentage true." }
      end
      out
    end

    def tool_search(args)
      found = tool_search_claims("query" => args["query"], "limit" => 10)
      { results: found[:claims].map { |c| { id: c[:id], title: "#{c[:plain_headline]} — #{c[:text]}", url: c[:url] } } }
    end

    def tool_fetch(args)
      claim = find_claim("claim_id" => args["id"])
      seq = Contribution.maximum(:seq)
      model = Scoring::Registry.default_model
      card = Cards::ClaimCard.call(claim, seq, model)
      why = Cards::Why.call(claim, seq, model)
      lines = [ "Claim: #{claim.canonical_text}", "Galedra says: #{card[:plain][:headline]}" ]
      lines << "Say instead: #{card[:plain][:say_instead]}" if card[:plain][:say_instead]
      lines << "Assessment: #{card[:headline]} under #{card[:model]} at snapshot #{seq}; review checks #{card[:review_checks]}"
      lines.concat(card[:labels])
      lines << "Strongest support: #{why[:strongest_support][:statement]}" if why[:strongest_support]
      lines << "Strongest contradiction: #{why[:strongest_contradiction][:statement]}" if why[:strongest_contradiction]
      lines << "What would most change this: #{why.dig(:what_would_most_change_this, :text)}" if why[:what_would_most_change_this]
      lines << "Provisional until audited. Model-conditional, not objective."
      { id: claim.id, title: claim.canonical_text, text: lines.join("\n"), url: url_for(claim),
        metadata: { type: claim.claim_type, assessment_state: why[:assessment_state], snapshot_seq: seq, model: model.full_name } }
    end

    def tool_share_card(args)
      claim = find_claim(args)
      seq = Contribution.maximum(:seq)
      card = Cards::ClaimCard.call(claim, seq, Scoring::Registry.default_model)
      { url: url_for(claim), card_url: "#{url_for(claim)}/card", image_url: "#{url_for(claim)}/card.png",
        headline: card[:plain][:headline], say_instead: card[:plain][:say_instead], text: claim.canonical_text }
    end

    private

    def brief(claim, seq, model)
      card = Cards::ClaimCard.call(claim, seq, model)
      { id: claim.id, text: claim.canonical_text, type: claim.claim_type, headline: card[:headline], plain_headline: card[:plain][:headline],
        similarity: claim.try(:similarity)&.to_f&.round(2), url: url_for(claim) }.compact
    end

    def find_claim(args)
      id = args["claim_id"].to_s
      raise ArgumentError, "claim_id is required" if id.empty?

      Claim.find_by(id: id) || raise(Ledger::Rejected.new([ { code: "NOT_FOUND", path: "$.claim_id", detail: "no such claim" } ]))
    end

    def url_for(claim) = "#{@base_url}/claims/#{claim.id}"

    def require_token!
      return if @token&.usable?

      raise Ledger::Rejected.new([ { code: "TOKEN_INVALID", path: "$", detail: "this tool writes to the log; connect an assistant at #{@base_url}/assistants/new and send its token as Authorization: Bearer" } ])
    end

    def error(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end

    def tool_error(id, errors)
      { jsonrpc: "2.0", id: id, result: { content: [ { type: "text", text: errors.map { |e| "#{e[:code] || e['code']}: #{e[:detail] || e['detail']}" }.join("\n") } ],
                                          structuredContent: { errors: errors }, isError: true } }
    end
  end
end
