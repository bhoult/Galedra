require "rails_helper"

RSpec.describe "MCP endpoint (Stage 14)", type: :request do
  before { release_models }

  let(:token) { Assistants::Connect.call(name: "Claude", provider: "anthropic").last }

  # A minimal MCP client: one JSON-RPC message per POST.
  def rpc(method, params = {}, id: 1, token: nil)
    headers = { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json, text/event-stream" }
    headers["Authorization"] = "Bearer #{token}" if token
    post "/mcp", params: { jsonrpc: "2.0", id: id, method: method, params: params }.to_json, headers: headers
    response.body.present? ? response.parsed_body : nil
  end

  def call_tool(name, arguments, token: nil)
    body = rpc("tools/call", { name: name, arguments: arguments }, token: token)
    [ body.dig("result", "structuredContent"), body.dig("result", "isError") ]
  end

  def bundle
    JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about").tap do |b|
      b["sources"].each { |s| s["retrieved_at"] = Time.now.utc.iso8601 }
    end
  end

  # Guidance asks for a report "equally when you got the job done but the way
  # through was wasteful"; the hint on the refusal itself said "if this stopped
  # you", and the hint is the text a caller reads at the moment it would decide.
  # An assistant worked around a refusal that named a field it had supplied and
  # never filed it, an hour after closing a report about that class (01a0c0d5).
  # The field took YYYY-MM-DD and said only "string", so an assistant with a
  # source known by year wrote something, was refused, and retried. The schema
  # now says the shape, and the refusal says what to do when the date is not
  # fully known — which is to leave it out, because a day nobody established is
  # a fact this record did not have.
  it "says the date shape in the schema and what to do when only the year is known" do
    described = Mcp::Server::TOOLS.flat_map { |t| JSON.generate(t).scan(/publication_date[^}]*}/) }
    expect(described).to be_any
    described.each do |bit|
      expect(bit).to include("YYYY-MM-DD"), "publication_date is described as a bare string somewhere"
      expect(bit).to include("Omit it")
    end

    body = rpc("tools/call", { name: "record_investigation", arguments: {
                 "sources" => [ { "handle" => "s", "type" => "WEBSITE", "title" => "A book", "url" => "https://example.test/b",
                                  "retrieved_at" => Time.now.utc.iso8601, "publication_date" => "1937" } ],
                 "claims" => [ { "handle" => "c", "text" => "A claim from a book known only by year.", "type" => "TEXTUAL" } ] } })
    detail = body.dig("result", "structuredContent", "errors")&.first&.dig("detail").to_s
    expect(detail).to include("whole date")
    expect(detail).to include("leave it out"), "the refusal has to say what to do, not only what is wrong"
  end

  # One message for three faults: an assistant passed its excerpt handles where
  # evidence handles belong — reasonable, since both are handles it named in the
  # same bundle — sent exactly two of them, and was told "expected at least two".
  it "names which handle is wrong in a group rather than blaming the count" do
    Investigations::Record
    errs = []
    add = ->(path, detail) { errs << detail }
    handles = { "q1" => "excerpts", "q2" => "excerpts", "e1" => "evidence", "e2" => "evidence" }

    Investigations::Validate.check_groups({ "members" => %w[q1 q2] }, "$.groups[0]", handles, add, nil)
    expect(errs.last).to include("members are evidence handles")
    expect(errs.last).to include("q1 is a handle in excerpts")
    expect(errs.last).not_to include("at least two"), "it sent two; the count was never the problem"

    Investigations::Validate.check_groups({ "members" => %w[e1] }, "$.groups[1]", handles, add, nil)
    expect(errs.last).to include("at least two"), "and when the count IS the problem, it says so"

    Investigations::Validate.check_groups({ "members" => %w[e1 zz] }, "$.groups[2]", handles, add, nil)
    expect(errs.last).to include("zz is not a handle in this bundle")

    errs.clear
    Investigations::Validate.check_groups({ "members" => %w[e1 e2] }, "$.groups[3]", handles, add, nil)
    expect(errs).to be_empty
  end

  # get_claim names a near miss when an id is one or two characters off; this
  # path said only "no such accepted claim", which is the same fault fixed in one
  # place and not in its class. The second case matters more than it looks: these
  # ids are UUIDv7, so the leading run is a millisecond clock and every claim
  # recorded in the same minute shares it — a wrong id that looks close at the
  # front is a different claim made at the same moment, not a near miss, and a
  # caller comparing leading characters concludes the opposite.
  it "says what to do about an attach_to that does not resolve" do
    Investigations::Record
    real = create_claim(register_key(display_name: "C").first, "A claim already here.", type: "TEXTUAL")
    same_minute = "#{real.id[0, 8]}#{SecureRandom.uuid[8..]}"

    detail = Investigations::Validate.attach_to_detail(same_minute)
    expect(detail).to include("timestamp every claim recorded in the same minute shares")
    expect(detail).to include("whole id")
    expect(detail).not_to include("Did you mean"), "a shared leading run is not a near miss"

    off_by_one = real.id.sub(/.\z/) { |ch| ch == "a" ? "b" : "a" }
    expect(Investigations::Validate.attach_to_detail(off_by_one)).to include("Did you mean #{real.id}?")

    expect(Investigations::Validate.attach_to_detail("00000000-0000-0000-0000-000000000000"))
      .to include("from search_claims or list_claims")
  end

  # Two assistants, the same outline, byte-identical guidance: one worked
  # eighteen leases and moved five claims, the other chose claims itself and
  # moved about twenty. Asked why, the first said the queue arrived as an
  # opening command while the alternative came later and conditionally, as an
  # escape hatch rather than a strategy. So the goal leads now, and the sentence
  # that prescribed the queue is gone from the line that rides on every result.
  it "says what the work is for before how to do it, and does not prescribe the queue" do
    work = Guidance.for(:work)
    goal = work.index("move checkable claims out of insufficient evidence")
    queue = work.index("next_task")
    expect(goal).to be_present
    expect(goal).to be < queue, "the goal has to arrive before the mechanism"
    expect(work).to include("claims moved, not in tasks submitted")
    expect(work).to include("list_claims"), "the other route is named, not merely implied"

    expect(Guidance::CONNECTED).not_to include("next_task"),
                                       "the always-on line told an assistant the queue was how to work open tasks"
    expect(Guidance::CONNECTED).to include("browser"), "while still saying what it was written to say"
  end

  # A connected assistant reached /assistants/new — a page written for a person
  # setting a connection up — read it as an instruction to connect, and stalled
  # on a sign-in it did not need, having already made a successful tool call. The
  # page cannot tell a person from an authenticated agent reading over their
  # shoulder, so the fact rides on every result instead.
  it "tells an assistant it is already connected, on every topic" do
    Guidance::TOPICS.each do |topic|
      text = Guidance.for(topic)
      expect(text).to include("You are already connected"), "#{topic} does not say so"
      expect(text).to include("not for you"), "#{topic} does not rule out the setup pages"
    end

    body = rpc("tools/call", { name: "list_tasks", arguments: {} })
    expect(body.dig("result", "structuredContent", "guidance", "text").to_s).to include("already connected")
  end

  it "asks for a report on a refusal that cost a step, not only one that stopped the work" do
    body = rpc("tools/call", { name: "get_claim", arguments: { "claim_id" => "not-a-uuid" } })
    hint = body.dig("result", "structuredContent", "hint")
    expect(body.dig("result", "isError")).to be(true)
    expect(hint).to include("worked around"), "waste noticed while succeeding is the case that never gets filed"
    expect(hint).not_to match(/\AIf this stopped you/), "the narrow wording contradicted Guidance"
    expect(Guidance::ASK).to include("wasteful"), "and the two have to agree"
  end

  it "initializes, lists the tools, records a bundle, and reads the card back under one token (#1)" do
    init = rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "spec", version: "0" } })
    expect(init.dig("result", "protocolVersion")).to eq("2025-06-18")
    expect(init.dig("result", "serverInfo", "name")).to eq("galedra")
    expect(init.dig("result", "instructions")).to include("never fetches URLs")
    expect(response.headers["MCP-Protocol-Version"]).to eq("2025-06-18")

    rpc("notifications/initialized")
    expect(response).to have_http_status(:accepted)

    tools = rpc("tools/list").dig("result", "tools").map { |t| t["name"] }
    expect(tools).to contain_exactly("search_claims", "get_claim", "record_investigation", "add_evidence", "explain", "share_card", "search", "fetch", "tag_claim", "list_topics",
                                     "list_tasks", "list_claims", "list_reports", "get_report", "respond_to_report", "next_task", "submit_task", "release_task",
                                     "revise_claim", "merge_claims", "revise_link", "open_task", "list_proposals", "accept_proposal", "request_feature", "report_bug", "next_content_review", "submit_content_review", "next_affiliation_review", "submit_affiliation_review", "create_outline", "get_outline", "record_inference",
                                     "open_thread", "list_threads", "get_thread", "respond_to_thread", "next_thread")

    data, err = call_tool("search_claims", { query: "Brackenridge bicycles" })
    expect(err).to be(false)
    expect(data["claims"]).to eq([])

    # Without a token the write still lands, as an anonymous assistant keyed to the caller.
    data, err = call_tool("record_investigation", bundle.merge("claims" => [ { "handle" => "t", "text" => "A tokenless MCP claim.", "type" => "TEXTUAL" } ], "links" => [], "evidence" => [], "excerpts" => [], "sources" => []))
    expect(err).to be(false)
    expect(Claim.find(data["claims"].first["id"]).contribution.principal_contributor).to be_anonymous
    expect(AssistantToken.find_by(source_key: Digest::SHA256.hexdigest("127.0.0.1|#{Date.current}"))).to be_present

    data, err = call_tool("record_investigation", bundle, token: token)
    expect(err).to be(false)
    expect(data["recorded"]).to be(true)
    ban = data["claims"].find { |c| c["handle"] == "ban" }

    data, = call_tool("search_claims", { query: "Brackenridge bicycles" })
    expect(data["claims"].map { |c| c["id"] }).to include(ban["id"])

    data, = call_tool("get_claim", { claim_id: ban["id"] })
    expect(data.dig("card", "plain", "headline")).to match(/against/)
    expect(data["url"]).to end_with("/claims/#{ban['id']}")

    data, = call_tool("explain", { claim_id: ban["id"], calculation: true })
    expect(data.dig("calculation", "stated_as")).to include("under #{Scoring::Registry.default_model.full_name} at snapshot")
    expect(data.dig("why", "strongest_contradiction", "statement")).to include("Motion 14")

    data, = call_tool("share_card", { claim_id: ban["id"] })
    expect(data["image_url"]).to end_with("/claims/#{ban['id']}/card.png")

    data, = call_tool("search", { query: "Brackenridge bicycles" })
    expect(data["results"].map { |r| r["id"] }).to include(ban["id"])
    expect(data["results"].first["title"]).to include("—")
    data, = call_tool("fetch", { id: ban["id"] })
    expect(data["text"]).to include("Galedra says: The evidence leans against this.")
    expect(data["text"]).to include("Strongest contradiction: Motion 14")
    expect(data["metadata"]["assessment_state"]).to eq("LEANS_CONTRADICTED")

    data, err = call_tool("add_evidence", { claim_id: ban["id"], source: bundle["sources"].last.except("handle"), excerpt: "Bicycles may be walked.", statement: "Bicycles may still be walked on the mall.", direction: "QUALIFY" }, token: token)
    expect(err).to be(false)
    expect(data["claims"].first).to include("id" => ban["id"], "created" => false)
  end

  it "answers protocol errors the JSON-RPC way and refuses GET" do
    body = rpc("no/such", {}, id: 7)
    expect(body["error"]).to include("code" => -32601)
    expect(body["id"]).to eq(7)

    body = rpc("tools/call", { name: "nope", arguments: {} })
    expect(body["error"]["code"]).to eq(-32602)

    post "/mcp", params: "{oops", headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body["error"]["code"]).to eq(-32700)

    post "/mcp", params: [ 1, 2 ].to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:bad_request)

    get "/mcp"
    expect(response).to have_http_status(:method_not_allowed)
  end

  it "accepts the token in the URL for connector screens that take only a URL" do
    post "/mcp/#{token}", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "record_investigation", arguments: bundle } }.to_json,
                          headers: { "CONTENT_TYPE" => "application/json" }
    expect(response.parsed_body.dig("result", "isError")).to be(false)
    expect(response.parsed_body.dig("result", "structuredContent", "recorded")).to be(true)

    # A presented but invalid credential is refused outright, so an OAuth client refreshes instead of falling through to anonymous use.
    post "/mcp/gal_wrong", params: { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "record_investigation", arguments: bundle } }.to_json,
                           headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body.dig("error", "code")).to eq(-32001)
    expect(response.headers["WWW-Authenticate"]).to include("oauth-protected-resource")
  end
  # Stage 31. This server cannot push notifications/tools/list_changed: there is
  # no stream to push it on. So it must tell clients not to cache the tool list,
  # or a corrected description waits for a reconnect that may never come.
  it "declares no listChanged and asks clients not to cache the tool list" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "initialize", params: {} }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json" }
    caps = response.parsed_body.dig("result", "capabilities", "tools")
    expect(caps["listChanged"]).to be(false)

    post "/mcp", params: { jsonrpc: "2.0", id: 2, method: "tools/list", params: {} }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json" }
    result = response.parsed_body["result"]
    expect(result["ttlMs"]).to eq(0)
    expect(result["cacheScope"]).to eq("public")

    get "/mcp"
    expect(response).to have_http_status(:method_not_allowed), "a stream would make listChanged: true honest; there is none"
  end
  # An assistant filed a feature request: the rules arrive verbatim on every
  # result, identical each time, and a long pass pays for them on every call.
  # They ride on every result on purpose, because that is the only channel
  # nothing caches. So a caller that has read them can say which version it
  # holds, and the default stays unchanged for one that says nothing.
  it "sends the rules until a caller says which version it already has" do
    body = rpc("tools/call", { name: "list_tasks", arguments: {} })
    guidance = body.dig("result", "structuredContent", "guidance")
    expect(guidance["version"]).to eq(Guidance::VERSION)
    expect(guidance["text"]).to be_present
    expect(guidance["repeat"]).to include("guidance_version")

    body = rpc("tools/call", { name: "list_tasks", arguments: { "guidance_version" => Guidance::VERSION } })
    quiet = body.dig("result", "structuredContent", "guidance")
    expect(quiet["version"]).to eq(Guidance::VERSION)
    expect(quiet["unchanged"]).to be(true)
    expect(quiet).not_to have_key("text")

    body = rpc("tools/call", { name: "list_tasks", arguments: { "guidance_version" => "1999-01-01" } })
    stale = body.dig("result", "structuredContent", "guidance")
    expect(stale["text"]).to be_present, "a stale version must still be corrected"
  end
end
