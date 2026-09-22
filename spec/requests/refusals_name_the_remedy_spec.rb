require "rails_helper"

# Stage 41. A refusal that names the rule and not the remedy leaves a worker to
# invent one. On 2026-09-22 an assistant hit TARGET_MISMATCH on a link it
# believed was wrongly counted and filed a feature request asking for a tool
# that already existed, because nothing at the point of refusal said so.
RSpec.describe "A refusal says what to do instead", type: :request do
  include GraphHelpers
  before { release_models }

  # Every tool named in a remedy has to exist, or the advice is worse than none.
  def tool_names = Mcp::Server::TOOLS.map { |t| t[:name] }

  # Words in a remedy that are not tools and are not meant to be. Anything else
  # snake_cased in those strings must name a real tool.
  NOT_TOOLS = %w[allowed_ops link_id source_location_id].freeze

  it "names tools that are in the registry" do
    named = [ Ledger::Appliers::TaskResult::REMEDY_FOR_LINK, Ledger::Appliers::TaskResult::REMEDY_FOR_OP ]
            .flat_map { |text| text.scan(/\b([a-z]+(?:_[a-z]+)+)\b/).flatten }
            .uniq - NOT_TOOLS

    # Every candidate must be a tool. The earlier version of this let a wholly
    # invented name through — it dropped any word no real tool shared four
    # opening characters with, so it could only ever catch a near-miss typo and
    # never the failure its own comment claims (code review, 2026-09-22).
    expect(named).not_to be_empty
    unknown = named.reject { |word| tool_names.include?(word) }
    expect(unknown).to eq([]), "remedies name #{unknown.join(', ')}, which are not tools"

    expect(Ledger::Appliers::TaskResult::REMEDY_FOR_LINK).to include("revise_link").and include("open_thread")
    expect(Ledger::Appliers::TaskResult::REMEDY_FOR_OP).to include("record_investigation").and include("add_evidence")
    expect(tool_names).to include("revise_link", "open_thread", "record_investigation", "add_evidence")
  end

  # The guard above, checked against a name nobody has ever shipped.
  it "would catch a remedy naming a tool that does not exist" do
    stub_const("Ledger::Appliers::TaskResult::REMEDY_FOR_OP", "Use the delete_everything tool instead.")
    named = Ledger::Appliers::TaskResult::REMEDY_FOR_OP.scan(/\b([a-z]+(?:_[a-z]+)+)\b/).flatten - NOT_TOOLS

    expect(named.reject { |word| tool_names.include?(word) }).to eq([ "delete_everything" ])
  end

  it "tells a worker superseding a link outside its packet where the link may be revised" do
    pair, = register_key
    source = create_source(pair, title: "A source")
    location = create_location(pair, source)
    claim = create_claim(pair, "A claim with evidence behind it.")
    # The packet is built when the task is made, so a link added afterwards is
    # outside it — which is the case the assistant hit: the packet held one older
    # link and the two it wanted to correct were not in it.
    task = create_task("QUALIFIER_CHECK", claim)
    outside = link_evidence(pair, create_evidence(pair, location), claim)
    worker, = register_reviewer

    expect {
      submit_result(worker, task, outcome: "QUALIFIERS_FOUND",
                    ops: [ { "op" => "SUPERSEDE_LINK", "link_id" => outside.id, "direction" => "QUALIFY",
                             "relevance_strength" => "MODERATE", "interpretive_steps" => 0 } ])
    }.to raise_error(Ledger::Rejected) { |e|
      detail = e.errors.map { |x| x[:detail] }.join(" ")
      expect(e.errors.map { |x| x[:code] }).to include("TARGET_MISMATCH")
      expect(detail).to include("revise_link"), "the refusal must name the tool that can do it"
      expect(detail).to include("open_thread"), "and the way to dispute the determination itself"
    }
  end

  it "tells a worker whose op is not allowed what belongs outside the task" do
    pair, = register_key
    claim = create_claim(pair, "A claim to check for qualifiers.")
    task = create_task("QUALIFIER_CHECK", claim)
    worker, = register_reviewer

    expect {
      submit_result(worker, task, outcome: "QUALIFIERS_FOUND",
                    ops: [ { "op" => "MERGE_CLAIMS", "from_claim_id" => claim.id, "into_claim_id" => claim.id } ])
    }.to raise_error(Ledger::Rejected) { |e|
      detail = e.errors.map { |x| x[:detail] }.join(" ")
      expect(e.errors.map { |x| x[:code] }).to include("OP_NOT_ALLOWED")
      expect(detail).to include("record_investigation")
    }
  end

  # And the worklist no longer offers them at all: of 254 claims placed in one
  # outline, 8 were merged or superseded, so about one pick in thirty was a
  # wasted round trip (bug report 6cc5282e).
  it "keeps a merged or superseded claim out of the worklist" do
    pair, = register_key
    source = create_source(pair, title: "A transcript", content: "A sentence of it. " * 30)
    result = append(action_type: "CREATE_SECTION", key_pair: pair,
                    payload: { "source_id" => source.id, "sections" => [ { "heading" => "All of it" } ] })
    section = Section.find(Ledger::Ids.derive(result.contribution.id, "section", 0))
    live = create_claim(pair, "A claim that stays current.")
    gone = create_claim(pair, "A claim that will be merged away.")
    [ live, gone ].each { |c| append(action_type: "PLACE_CLAIM", key_pair: pair, payload: { "claim_id" => c.id, "section_id" => section.id }) }

    token = AssistantToken.find_by_token(Assistants::Connect.call(name: "Worker", provider: "other").last)
    listed = lambda do
      out = Mcp::Server.new(token: token, base_url: "http://localhost:3000")
                       .call_tool("name" => "list_claims", "arguments" => { "section_id" => section.id })
      out[:structuredContent][:claims].map { |c| c[:id] }
    end
    expect(listed.call).to include(live.id, gone.id)

    append(action_type: "MERGE_CLAIMS", key_pair: pair,
           payload: { "from_claim_id" => gone.id, "into_claim_id" => live.id, "basis" => "SAME_ASSERTION" })

    expect(listed.call).to eq([ live.id ]), "a claim the write path refuses must not be offered as work"
  end

  # The worklist used to offer these, so the refusal was the first anyone heard
  # of it. It now names the claim the work belongs to.
  it "names the claim a merged one became" do
    pair, = register_key
    old_claim = create_claim(pair, "A claim that will be merged away.")
    kept = create_claim(pair, "The claim it merges into.")
    append(action_type: "MERGE_CLAIMS", key_pair: pair,
           payload: { "from_claim_id" => old_claim.id, "into_claim_id" => kept.id, "basis" => "SAME_ASSERTION" })

    expect {
      link_evidence(pair, create_evidence(pair, create_location(pair, create_source(pair))), Claim.find(old_claim.id))
    }.to raise_error(Ledger::Rejected) { |e|
      detail = e.errors.map { |x| x[:detail] }.join(" ")
      expect(e.errors.map { |x| x[:code] }).to include("CLAIM_NOT_CURRENT")
      expect(detail).to include(kept.id)
      expect(detail).to include("record this against that claim instead")
    }
  end
  # The auth refusals were outside this spec until 2026-09-22, which is how the
  # anonymous `next_task` wall shipped naming a remedy that meant abandoning the
  # session. An external agent hit it and filed `01a0ca28` asking for a token
  # type that mostly existed. The rule is right; the remedy has to be the one
  # that keeps the identity the work was recorded under.
  describe "the wall an anonymous assistant hits at the task queue" do
    def rpc_tool(name, arguments)
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                             params: { name: name, arguments: arguments } }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
      response.parsed_body.dig("result", "structuredContent")
    end

    it "names the adoption link that keeps this session's identity" do
      data = rpc_tool("next_task", {})

      expect(data["errors"].map { |e| e["code"] }).to include("TOKEN_INVALID")
      detail = data["errors"].map { |e| e["detail"] }.join(" ")
      token = AssistantToken.order(:created_at).last
      expect(token).to be_anonymous
      expect(detail).to include(Assistants::Adopt.adopt_url(token, "http://www.example.com")),
                        "the refusal must name the adoption link for the token in hand"
      expect(detail).to include("keep the token you are already using")
    end

    # A remedy is worth what its link is worth: /adopt/:code has to be routed,
    # or the advice sends a worker to a 404 and it files a feature request
    # instead.
    it "names a link this node actually serves" do
      rpc_tool("next_task", {})
      token = AssistantToken.order(:created_at).last

      expect(Rails.application.routes.recognize_path("/adopt/#{token.adoption_code}"))
        .to include(controller: "adoptions", action: "show")
    end

    # Adoption is only a remedy while there is a token to adopt. With none at
    # all there is nothing to keep, and the refusal correctly says where to get
    # an identity rather than inventing an adoption link for a token that does
    # not exist.
    it "does not offer adoption when there is no token to adopt" do
      server = Mcp::Server.new(token: nil, base_url: "http://www.example.com", read_only: false)

      expect { server.send(:require_delegation!) }.to raise_error(Ledger::Rejected) { |e|
        detail = e.errors.map { |x| x[:detail] }.join(" ")
        expect(detail).to include("/assistants/new")
        expect(detail).not_to include("/adopt/")
      }
    end
  end
  # A refusal has to describe the caller's request. `get_outline` with no
  # arguments answered "no such section" — an assertion about a section nobody
  # named — and a live worker called it twice with the wrong argument name
  # because the refusal never said the argument was missing (2026-09-22).
  describe "a required argument that was not sent" do
    def rpc_tool(name, arguments)
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                             params: { name: name, arguments: arguments } }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
      response.parsed_body.dig("result", "structuredContent")
    end

    it "says the argument is missing, and names what the call did carry" do
      data = rpc_tool("get_outline", { "task_id" => "not-a-section" })

      expect(data["errors"].map { |e| e["code"] }).to eq([ "SCHEMA_INVALID" ])
      detail = data["errors"].first["detail"]
      expect(detail).to include("section_id is required and was not sent")
      expect(detail).to include("task_id"), "a caller who sent the wrong name must be told which name they sent"
      expect(detail).not_to include("no such section"), "nothing may be asserted about a section the caller never named"
    end

    it "says so even when nothing at all was sent" do
      data = rpc_tool("get_outline", {})

      expect(data["errors"].first["detail"]).to include("this call carried no arguments")
    end

    # The check must not swallow the genuine case: an id that was sent and does
    # not resolve is still NOT_FOUND, and that message was never wrong.
    it "still reports a not-found id as not found" do
      data = rpc_tool("get_outline", { "section_id" => "01a00000-0000-7000-8000-000000000000" })

      expect(data["errors"].map { |e| e["code"] }).to eq([ "NOT_FOUND" ])
      expect(data["errors"].first["detail"]).to eq("no such section")
    end

    # Driven by each tool's own declared `required`, so a tool added later is
    # covered without anybody remembering to add it here.
    it "covers every tool that declares a required argument" do
      declared = Mcp::Server::TOOLS.select { |t| Array(t.dig(:inputSchema, :required)).any? }
      expect(declared.size).to be > 20

      declared.each do |tool|
        data = rpc_tool(tool[:name], {})
        next if data.nil? || data["errors"].nil?

        expect(data["errors"].first["detail"]).to include("is required and was not sent"),
                                                  "#{tool[:name]} refused an empty call without saying what was missing"
      end
    end
  end
end
