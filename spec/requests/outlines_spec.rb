require "rails_helper"

RSpec.describe "Large requests from a connector (Stage 21)", type: :request do
  include LedgerHelpers
  before { release_models }

  let(:password) { "correct horse battery staple" }
  let(:requester_user) { User.create!(email_address: "req@example.com", password: password) }
  let(:requester) { Assistants::Connect.call(user: requester_user, name: "Requester", provider: "anthropic").last }
  let(:volunteer) { Assistants::Connect.call(user: User.create!(email_address: "vol@example.com", password: password), name: "Volunteer", provider: "openai").last }

  def call_tool(name, arguments, tok)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{tok}" }
    body = response.parsed_body
    [ body.dig("result", "structuredContent"), body.dig("result", "isError") ]
  end

  def outline_args
    { statement: "Moonshots episode 123 https://pod.example/123",
      source: { type: "AUDIO", title: "Moonshots episode 123", url: "https://pod.example/123", retrieved_at: Time.now.utc.iso8601 },
      sections: [ { handle: "root", heading: "Moonshots episode 123", sections: [
        { handle: "align", heading: "LLM alignment", sections: [
          { handle: "openai", heading: "OpenAI", locator: { type: "TIME_RANGE", start: "00:41:10", end: "00:47:30" }, anchor: "So let's talk about what OpenAI published" },
          { handle: "anthropic", heading: "Anthropic", locator: { type: "TIME_RANGE", start: "00:47:30", end: "00:52:00" }, anchor: "Anthropic took a different route" } ] },
        { handle: "math", heading: "Math is cooked", sections: [
          { handle: "prize", heading: "Millennium Prize", locator: { type: "TIME_RANGE", start: "01:10:00", end: "01:16:00" }, anchor: "the Millennium Prize problems" } ] } ] } ] }
  end

  it "records the structure and the jobs, then lets a volunteer extract, the requester accept, and the requester record a leaf directly (#1, #2, #3)" do
    data, err = call_tool("create_outline", outline_args, requester)
    expect(err).to be(false), data.inspect
    expect(data["recorded"]).to be(true)
    expect(data["sections"].keys).to match_array(%w[root align openai anthropic math prize])
    expect(data["tasks_opened"]).to eq(3)
    expect(data["next"]).to include("ask whether they want you to start")
    expect(data["share_line"]).to start_with("Checked in Galedra: Moonshots episode 123 · 0 claims recorded, 0 checked · no claims yet")
    root_id = data["root_id"]
    openai_id = data["sections"]["openai"]["id"]
    expect(Section.find(openai_id).path).to eq([ "Moonshots episode 123", "LLM alignment", "OpenAI" ])
    expect(Task.where(task_type: "CLAIM_EXTRACTION", section_id: openai_id).count).to eq(1)
    expect(Source.find_by(canonical_uri: "https://pod.example/123").content).to be_nil
    expect(SourceLocation.where(source_id: Source.find_by(canonical_uri: "https://pod.example/123").id).count).to eq(3)

    # Idempotent: the same bundle again records once.
    again, = call_tool("create_outline", outline_args, requester)
    expect(Section.where(root_id: root_id).count).to eq(6)

    # The requester cannot lease the extraction tasks it opened; a volunteer can, scoped to the outline.
    mine, = call_tool("next_task", { section_id: root_id }, requester)
    expect(mine["available"]).to be(false)
    task, err = call_tool("next_task", { section_id: root_id, types: [ "CLAIM_EXTRACTION" ] }, volunteer)
    expect(err).to be(false), task.inspect
    expect(task["task_type"]).to eq("CLAIM_EXTRACTION")
    expect(task["context"]["section"]["path"].first).to eq("Moonshots episode 123")
    expect(task["context"]["excerpts"].first["untrusted_excerpt"]).to include("OpenAI published").or include("Anthropic took").or include("Millennium Prize")
    listed, = call_tool("list_tasks", { section_id: root_id }, volunteer)
    expect(listed["open"]).to eq(2) # one of the three is leased
    expect(listed["by_outline"].first["root_id"]).to eq(root_id)

    data, err = call_tool("submit_task", { task_id: task["task_id"], outcome: "CLAIMS_FOUND", answer: { claims: [
      { handle: "c1", text: "OpenAI published its Preparedness Framework in December 2023.", type: "HISTORICAL" },
      { handle: "c2", text: "The framework defines four risk categories.", type: "TEXTUAL" } ] } }, volunteer)
    expect(err).to be(false), data.inspect
    expect(data["accepted"]).to be(false)
    leaf_id = Task.find(task["task_id"]).section_id
    pending_claims = Claim.where(canonical_text: [ "OpenAI published its Preparedness Framework in December 2023.", "The framework defines four risk categories." ])
    expect(pending_claims.count).to eq(2)
    expect(pending_claims.all? { |c| c.accepted_seq.nil? }).to be(true)
    expect(ClaimPlacement.where(section_id: leaf_id).count).to eq(2)
    get "/sections/#{leaf_id}"
    expect(response.body).to include("2 proposed claims awaiting acceptance")
    expect(response.body).not_to include("Preparedness Framework")

    proposals, = call_tool("list_proposals", {}, requester)
    result_id = Contribution.where(action_type: "TASK_RESULT").last.id
    expect(proposals.to_json).to include(result_id)
    rejected, err = call_tool("accept_proposal", { contribution_id: result_id }, volunteer)
    expect(err).to be(true)
    accepted, err = call_tool("accept_proposal", { contribution_id: result_id }, requester)
    expect(err).to be(false), accepted.inspect
    expect(pending_claims.reload.all? { |c| c.reload.accepted_seq.present? }).to be(true)
    expect(Task.where(task_type: %w[OPPOSING_EVIDENCE_SEARCH QUALIFIER_CHECK], target_id: pending_claims.map(&:id)).count).to eq(4)
    expect(Task.where(task_type: "EVIDENCE_VERIFICATION", target_id: pending_claims.map(&:id)).count).to eq(2)
    get "/sections/#{leaf_id}"
    expect(response.body).to include("Preparedness Framework")

    # The requester records another leaf directly: accepted at once, extraction task cancelled, share line is the outline's counts.
    other_leaf = (data = call_tool("get_outline", { section_id: root_id }, requester).first; nil)
    other_leaf_id = Task.where(task_type: "CLAIM_EXTRACTION", status: "OPEN").first.section_id
    bundle = { statement: "leaf", sources: [ { handle: "s", type: "AUDIO", title: "Moonshots episode 123", url: "https://pod.example/123", retrieved_at: Time.now.utc.iso8601 } ],
               excerpts: [ { handle: "x", source: "s", kind: "TRANSCRIPTION", text: "Anthropic took a different route with its constitution." } ],
               claims: [ { handle: "c", text: "Anthropic published a constitution for its models.", type: "HISTORICAL", section: other_leaf_id } ],
               evidence: [ { handle: "e", excerpt: "x", statement: "The host says Anthropic published a constitution." } ],
               links: [ { evidence: "e", claim: "c", direction: "SUPPORT" } ] }
    data, err = call_tool("record_investigation", bundle, requester)
    expect(err).to be(false), data.inspect
    expect(data["recorded"]).to be(true)
    expect(data["share_line"]).to start_with("Checked in Galedra: Moonshots episode 123 · 3 claims recorded, 1 checked · 1 supported")
    expect(data["share_line"]).to include("/sections/#{root_id}")
    expect(Task.where(task_type: "CLAIM_EXTRACTION", section_id: other_leaf_id).first).to have_attributes(status: "CANCELLED", cancelled_reason: "RECORDED_BY_REQUESTER")
    claim = Claim.find_by(canonical_text: "Anthropic published a constitution for its models.")
    expect(claim.accepted_seq).to be_present
    expect(ClaimPlacement.where(claim_id: claim.id, section_id: other_leaf_id).count).to eq(1)
    investigation = Investigation.where(section_id: root_id).order(:created_at).last
    get "/investigations/#{investigation.id}"
    expect(response).to redirect_to(section_path(root_id))

    tree, = call_tool("get_outline", { section_id: root_id }, requester)
    expect(tree["counts"]["claims"]).to eq(3)
    expect(tree.to_json).not_to include("probability")
  end

  it "refuses a large unsectioned bundle, caps named assistants at 1,000, and validates the outline shape (#4)" do
    claims = (1..41).map { |i| { handle: "c#{i}", text: "Claim number #{i} of many.", type: "OBSERVATIONAL" } }
    data, err = call_tool("record_investigation", { statement: "big", claims: claims }, requester)
    expect(err).to be(true)
    expect(data.to_json).to include("create_outline")
    expect(AssistantToken.find_by_token(requester).daily_cap).to eq(1_000)
    anon = Assistants::Connect.call(user: nil, name: "Anon", provider: "other").first
    expect(anon.daily_cap).to eq(200)

    bad = outline_args.merge(sections: [ { handle: "a", heading: "One" }, { handle: "b", heading: "Two" } ])
    data, err = call_tool("create_outline", bad, requester)
    expect(err).to be(true)
    expect(data.to_json).to include("one root")
    bad = outline_args
    bad[:sections][0][:sections][0][:sections][0][:anchor] = "x" * 301
    data, err = call_tool("create_outline", bad, requester)
    expect(err).to be(true)
    expect(data.to_json).to include("300")
  end

  it "keeps the whole outline on the page as you go down it, marking where you are" do
    pair, = register_key
    source = create_source(pair, title: "A long source")
    result = append(action_type: "CREATE_SECTION", key_pair: pair,
                    payload: { "source_id" => source.id, "sections" => [ { "heading" => "Root", "sections" => [
                      { "heading" => "First part", "sections" => [ { "heading" => "A leaf" } ] },
                      { "heading" => "Second part" }, { "heading" => "Third part" } ] } ] })
    root = Section.find(Ledger::Ids.derive(result.contribution.id, "section", 0))
    first = root.children.order(:position).first
    leaf = first.children.order(:position).first

    # Deep in the outline, its siblings are still there: building the tree from
    # the section being read made everything else disappear as you descended.
    get "/sections/#{leaf.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Second part").and include("Third part").and include("First part")
    expect(response.body).to include(%(<summary class="current">))
    expect(response.body).to include("The whole outline, with where you are marked.")

    # The counts still describe the section being read, not the whole outline.
    expect(response.body).to include("Nothing under this section yet.")
    get "/sections/#{root.id}"
    expect(response.body).not_to include("Nothing under this section yet.")
  end
end
