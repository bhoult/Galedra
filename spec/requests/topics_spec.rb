require "rails_helper"

RSpec.describe "Topics (Stage 15)", type: :request do
  before { release_models }

  let(:json) { { "CONTENT_TYPE" => "application/json" } }
  let(:curator) { register_key(display_name: "Curator").first }

  def tag(pair, claim, topics, note: nil, delegation: nil)
    append(action_type: "TAG_CLAIM", key_pair: pair, payload: { "claim_id" => claim.id, "topics" => topics, "note" => note }.compact, delegation_id: delegation&.id)
  end

  it "records, validates, supersedes, and replays tags (#1)" do
    claim = create_claim(curator, "Brain scans show all brain areas are active.")
    first = tag(curator, claim, [ "science/neuroscience", "health" ])
    rows = ClaimTopic.where(contribution_id: first.contribution.id).order(:topic)
    expect(rows.map(&:topic)).to eq([ "health", "science/neuroscience" ])
    expect(rows.first.accepted_seq).to be_present
    seq = Contribution.maximum(:seq)
    expect(Topics.for_claim(claim, seq)).to contain_exactly("science/neuroscience", "health")

    expect_rejected("TOPIC_UNKNOWN") { tag(curator, claim, [ "science/astrology" ]) }
    expect_rejected("SCHEMA_INVALID") { tag(curator, claim, []) }
    expect_rejected("SCHEMA_INVALID") { tag(curator, claim, [ "health", "health" ]) }
    expect_rejected("SCHEMA_INVALID") { tag(curator, claim, Topics.all.first(6)) }

    second = tag(curator, claim, [ "science/neuroscience" ], note: "narrowed")
    later = Contribution.maximum(:seq)
    expect(Topics.for_claim(claim, later)).to eq([ "science/neuroscience" ])
    expect(Topics.for_claim(claim, seq)).to contain_exactly("science/neuroscience", "health")
    expect(ClaimTopic.find_by!(contribution_id: first.contribution.id, topic: "health").replaced_seq).to eq(second.contribution.seq)

    reviewer, = register_reviewer
    proposal = tag(reviewer, claim, [ "society/media" ])
    expect(proposal.contribution.current_status).to eq("PENDING")
    expect(Topics.for_claim(claim, Contribution.maximum(:seq))).to eq([ "science/neuroscience" ])
    accept(curator, proposal.contribution)
    expect(Topics.for_claim(claim, Contribution.maximum(:seq))).to contain_exactly("science/neuroscience", "society/media")

    before = Ledger::TableDigest.projections
    Ledger::Replay.call
    expect(Ledger::TableDigest.projections).to eq(before)
    expect(before.keys).to include("claim_topics")
  end

  it "takes topics from a bundle and shows them on the page, the API, and the MCP tool (#2)" do
    bundle = JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about")
    bundle["sources"].each { |s| s["retrieved_at"] = "2026-09-18T12:00:00Z" }
    bundle["claims"][0]["topics"] = [ "law/legislation", "society/crime" ]
    bundle["claims"][1]["topics"] = [ "law/legislation" ]
    post "/api/v1/investigations", params: bundle.to_json, headers: json
    expect(response).to have_http_status(:created)
    ban = response.parsed_body["claims"].first
    kinds = Contribution.in_order.pluck(:action_type)
    expect(kinds.index("TAG_CLAIM")).to be > kinds.index("CREATE_CLAIM")

    get "/claims/#{ban['id']}"
    expect(response.body).to include("Legislation")
    expect(response.body).to include("Topics")
    get "/api/v1/claims/#{ban['id']}"
    expect(response.parsed_body.dig("claim", "topics")).to contain_exactly("law/legislation", "society/crime")

    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "get_claim", arguments: { claim_id: ban["id"] } } }.to_json, headers: json
    expect(response.parsed_body.dig("result", "structuredContent", "topics")).to include("law/legislation")

    bad = bundle.merge("claims" => [ { "handle" => "x", "text" => "Unknown topic.", "type" => "TEXTUAL", "topics" => [ "nonsense/thing" ] } ])
    post "/api/v1/investigations", params: bad.to_json, headers: json
    expect(response).to have_http_status(422)
    expect(response.parsed_body["errors"].first["path"]).to eq("$.claims[0].topics")

    post "/mcp", params: { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "list_topics", arguments: {} } }.to_json, headers: json
    expect(response.parsed_body.dig("result", "structuredContent", "topics").map { |t| t["path"] }).to include("science", "religion")
    post "/mcp", params: { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "tag_claim", arguments: { claim_id: ban["id"], topics: [ "politics/government" ] } } }.to_json, headers: json
    expect(response.parsed_body.dig("result", "isError")).to be(false)
  end

  it "rolls counts up to the parent topic with no probability on the page (#3)" do
    claim = create_claim(curator, "Cells divide.")
    other = create_claim(curator, "Rivers erode.")
    tag(curator, claim, [ "science/biology" ])
    tag(curator, other, [ "science/earth" ])
    get "/topics"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Science")

    get "/topics/science"
    expect(response.body).to include("Cells divide.")
    expect(response.body).to include("Rivers erode.")
    expect(response.body).to include("Insufficient evidence")
    expect(response.body).not_to match(/\b0\.\d{4}\b/)
    get "/topics/science/biology"
    expect(response.body).to include("Cells divide.")
    expect(response.body).not_to include("Rivers erode.")
    get "/topics/science/astrology"
    expect(response).to have_http_status(:not_found)

    get "/claims?topic=science"
    expect(response.body).to include("Cells divide.")
    get "/api/v1/claims?topic=science/earth"
    expect(response.parsed_body["claims"].map { |c| c["text"] }).to eq([ "Rivers erode." ])
    get "/api/v1/topics"
    science = response.parsed_body["topics"].find { |t| t["path"] == "science" }
    expect(science["claims"]).to eq(2)
    expect(science["children"].find { |c| c["path"] == "science/biology" }["claims"]).to eq(1)
  end

  it "routes tasks for a tagged claim to the topic's domain (#4)" do
    claim = create_claim(curator, "The Watchers taught metallurgy, the narrative says.")
    tag(curator, claim, [ "history/ancient" ])
    expect(Audits::Policy.domains).to include("ancient_near_east", "science", "religion")
    token, = Assistants::Connect.call(name: "Claude", provider: "anthropic")
    expect(Topics.domain_for_claim(claim, Contribution.maximum(:seq))).to eq("ancient_near_east")

    bundle = { "claims" => [ { "handle" => "h", "attach_to" => claim.id } ], "sources" => [ { "handle" => "s", "type" => "WEBSITE", "title" => "T", "url" => "https://example.org/t", "content_hash" => "sha256:#{'ab' * 32}", "retrieved_at" => "2026-09-18T12:00:00Z" } ],
               "excerpts" => [ { "handle" => "x", "source" => "s", "text" => "The narrative says the Watchers taught metallurgy." } ], "evidence" => [ { "handle" => "e", "excerpt" => "x", "statement" => "It says so." } ],
               "links" => [ { "evidence" => "e", "claim" => "h", "direction" => "SUPPORT" } ] }
    Investigations::Record.call(token, bundle, base_url: "http://www.example.com")
    fresh = { "claims" => [ { "handle" => "n", "text" => "The narrative attributes weapon-making to Azazel.", "type" => "TEXTUAL", "topics" => [ "history/ancient" ] } ] }
    result = Investigations::Record.call(token, fresh, base_url: "http://www.example.com")
    expect(Task.where(target_id: result[:ids]["n"]).pluck(:domain).uniq).to eq([ "ancient_near_east" ])

    reviewer_pair, reviewer = register_reviewer
    task = Task.find_by!(target_id: result[:ids]["n"], task_type: "OPPOSING_EVIDENCE_SEARCH")
    submission = submit_result(reviewer_pair, task, outcome: "NONE_FOUND", ops: [])
    auditor_pair, = register_key(display_name: "Auditor", identity_tier: "ESTABLISHED")
    audit(auditor_pair, submission.contribution, result: "CONFIRMED", type: "SOURCE_CHECK")
    buckets = Reputation::Calculate.buckets(contributor_id: reviewer.id, snapshot_seq: Contribution.maximum(:seq))
    expect(buckets.map { |b| b[:domain] }).to include("ancient_near_east")
  end

  it "restricts tagging through a delegation and keeps the demo goldens (#5)" do
    principal_pair, agent_pair, agent, _delegation = principal_with_agent
    claim = create_claim(principal_pair, "Delegated tagging.")
    limited = delegate(principal_pair, agent, permissions: { "allowed_task_types" => Tasks::Types::ALL, "domains" => Audits::Policy.domains, "direct_work" => true, "topics" => [ "science" ] })
    tag(agent_pair, claim, [ "science/physics" ], delegation: limited)
    expect_rejected("DELEGATION_INVALID") { tag(agent_pair, claim, [ "politics/elections" ], delegation: limited) }

    graph = build_public_demo
    golden_cases_for("public").each do |kase|
      claim = graph.claims.fetch(kase["claim"])
      seq = graph.checkpoints.fetch(kase["checkpoint"])
      model = Scoring::Registry.find(kase["model"])
      expect(golden_fields(Scoring::Score.call(claim, seq, model))).to eq(kase["expected"]), "#{kase['claim']} at #{kase['checkpoint']}"
    end
  end
end
