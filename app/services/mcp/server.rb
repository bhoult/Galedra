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
            "Never record claims about identifiable private individuals. Report the plain headline and the link, and say the result is provisional until audited."

    TOOLS = [
      { name: "search_claims", description: "Search accepted claims by words. Always call this first: if the claim is already recorded, report its card and URL instead of recording a twin.",
        inputSchema: { type: "object", properties: { query: { type: "string", description: "Words from the claim" }, limit: { type: "integer", minimum: 1, maximum: 50, default: 10 } }, required: [ "query" ] } },
      { name: "get_claim", description: "The answer card for one claim: a plain headline, what to say instead when the evidence supports it, review checks, labels, counted evidence for and against, and the URL. No probability here; use explain with calculation: true for the number.",
        inputSchema: { type: "object", properties: { claim_id: { type: "string" } }, required: [ "claim_id" ] } },
      { name: "record_investigation", description: "Record what you found, all at once: sources by link and content hash, quoted excerpts, atomic typed claims, evidence statements, and links (SUPPORT, CONTRADICT, QUALIFY, NEUTRAL) with interpretive steps. Needs a connected assistant token. If similar accepted claims exist the call returns them under existing and records nothing; resubmit with attach_to on those claims, or on_duplicate: create. " + RULES,
        inputSchema: { type: "object", properties: {
          sources: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, type: { type: "string", enum: Source::TYPES }, title: { type: "string" }, url: { type: "string" }, content_hash: { type: "string", description: "sha256:<hex> of the bytes you read" }, retrieved_at: { type: "string", description: "RFC 3339" }, publisher: { type: "string" }, publication_date: { type: "string" } }, required: %w[handle type title url content_hash retrieved_at] } },
          excerpts: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, source: { type: "string" }, kind: { type: "string", enum: %w[QUOTE TRANSCRIPTION] }, text: { type: "string" } }, required: %w[handle source text] } },
          claims: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, text: { type: "string" }, type: { type: "string", enum: Claim::TYPES }, attach_to: { type: "string", description: "An existing claim id instead of text and type" } }, required: [ "handle" ] } },
          evidence: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, excerpt: { type: "string" }, statement: { type: "string" }, observation_type: { type: "string", enum: EvidenceItem::OBSERVATION_TYPES } }, required: %w[handle excerpt statement] } },
          links: { type: "array", items: { type: "object", properties: { evidence: { type: "string" }, claim: { type: "string" }, direction: { type: "string", enum: EvidenceClaimLink::DIRECTIONS }, strength: { type: "string", enum: EvidenceClaimLink::STRENGTHS }, steps: { type: "integer", minimum: 0, maximum: EvidenceClaimLink::MAX_STEPS }, note: { type: "string" } }, required: %w[evidence claim direction] } },
          groups: { type: "array", items: { type: "object", properties: { handle: { type: "string" }, type: { type: "string", enum: IndependenceGroup::TYPES }, members: { type: "array", items: { type: "string" } } }, required: %w[handle members] } },
          on_duplicate: { type: "string", enum: %w[ask create], default: "ask" }
        }, required: [ "claims" ] } },
      { name: "add_evidence", description: "Attach one quoted passage to an existing claim as evidence for, against, or qualifying it. Needs a connected assistant token. " + RULES,
        inputSchema: { type: "object", properties: { claim_id: { type: "string" }, source: { type: "object", properties: { type: { type: "string", enum: Source::TYPES }, title: { type: "string" }, url: { type: "string" }, content_hash: { type: "string" }, retrieved_at: { type: "string" }, publisher: { type: "string" } }, required: %w[type title url content_hash retrieved_at] }, excerpt: { type: "string" }, excerpt_kind: { type: "string", enum: %w[QUOTE TRANSCRIPTION], default: "QUOTE" }, statement: { type: "string" }, direction: { type: "string", enum: EvidenceClaimLink::DIRECTIONS }, strength: { type: "string", enum: EvidenceClaimLink::STRENGTHS, default: "DIRECT" }, steps: { type: "integer", default: 0 }, note: { type: "string" } }, required: %w[claim_id source excerpt statement direction] } },
      { name: "explain", description: "Why a claim stands where it does: strongest counted support and contradiction, suppressed dependents, review gaps, and what would most change it. With calculation: true, also the probability, always stated with its model and snapshot; never present it as a percentage true.",
        inputSchema: { type: "object", properties: { claim_id: { type: "string" }, calculation: { type: "boolean", default: false } }, required: [ "claim_id" ] } },
      { name: "share_card", description: "A link and image for pasting into a social post: the plain headline, what to say instead, and the claim URL. The card never shows a number.",
        inputSchema: { type: "object", properties: { claim_id: { type: "string" } }, required: [ "claim_id" ] } }
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
