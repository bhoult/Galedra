require "rails_helper"

RSpec.describe "Work open tasks from a connector (Stage 18)", type: :request do
  before { release_models }

  let(:curator) { register_key(display_name: "Curator").first }
  let(:user) { User.create!(email_address: "me@example.com", password: "correct horse battery staple") }
  let!(:token) { Assistants::Connect.call(user: user, name: "Claude", provider: "anthropic").last }
  let(:model) { Scoring::Registry.default_model }

  def rpc(method, params = {}, token: nil)
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["Authorization"] = "Bearer #{token}" if token
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json, headers: headers
    response.parsed_body
  end

  def call_tool(name, arguments, tok = token)
    body = rpc("tools/call", { name: name, arguments: arguments }, token: tok)
    [ body.dig("result", "structuredContent"), body.dig("result", "isError") ]
  end

  def errors_of(data) = data["errors"].map { |e| e["code"] }

  def statements
    n = 0
    counter = ->(*, payload) { n += 1 unless payload[:name].to_s == "SCHEMA" || payload[:sql].to_s.start_with?("BEGIN", "COMMIT") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    n
  end

  # list_tasks asked every task for its open slots — two queries — then asked the
  # whole set again to total them, then a Section per task for the outline
  # grouping. Over ~840 tasks that was 3,714 statements to return five tasks and
  # some counts (docs/experiments/2026-09-20-second-connector-run.md, finding 4).
  # The queue handed an assistant six unsettleable claims in a row. It noticed,
  # filed a feature request, and was handed two more, because next_task filtered
  # on task type and domain and neither can express "a claim whose state can
  # change" (docs/experiments/2026-09-20-second-connector-run.md, finding 2).
  # get_outline returns whole trees and full text; asked for a 255-claim outline
  # it overran the caller's own token limit mid-chapter, and roughly sixty
  # checkable claims were never recovered
  # (docs/experiments/2026-09-20-second-connector-run.md).
  it "lists the claims that still need outside sources, filtered and paginated" do
    source = create_source(curator, title: "Episode for the worklist")
    created = append(action_type: "CREATE_SECTION", key_pair: curator, payload: { "source_id" => source.id, "sections" => [ { "heading" => "Episode" } ] })
    root = Section.where(contribution_id: created.contribution.id).first
    checkable = create_claim(curator, "Remote work raised measured output by 14 per cent in the trial.", type: "QUANTITATIVE", section_id: root.id)
    forecast = create_claim(curator, "Yang-Mills will fall next.", type: "FORECAST", section_id: root.id)

    data, err = call_tool("list_claims", { "section_id" => root.id, "checkable" => true })
    expect(err).to be(false), data.inspect
    expect(data["claims"].map { |c| c["id"] }).to eq([ checkable.id ]), "a FORECAST is not checkable"
    expect(data["claims"].first.keys).to match_array(%w[id text type state url]), "id, text, type and state only: the whole point is that it fits"

    all, = call_tool("list_claims", { "section_id" => root.id })
    expect(all["total"]).to eq(2)
    page, = call_tool("list_claims", { "section_id" => root.id, "limit" => 1 })
    expect(page["claims"].size).to eq(1)
    expect(page["more"]).to be(true), "a caller must be able to tell there is another page"
  end

  # list_tasks said sixty content reviews were waiting while next_content_review
  # said none awaited, seconds apart. Both were right: all sixty were that
  # assistant's own words, which it may not review (01a0c085).
  it "separates reviews waiting from reviews this caller may take" do
    call_tool("report_bug", { happened: "something to review", expected: "no crash" })
    expect(ContentReview.pending.count).to be_positive

    data, err = call_tool("list_tasks", {})
    expect(err).to be(false), data.inspect
    expect(data["content_reviews_pending"]).to eq(ContentReview.pending.count)
    expect(data["content_reviews_for_you"]).to eq(0), "its own words are not reviewable by it"

    mine, err = call_tool("next_content_review", {})
    expect(err).to be(false)
    expect(mine["available"]).to be(false), "and the two tools must not contradict each other"

    # Somebody else's words are both counted and offered.
    other = Assistants::Connect.call(user: User.create!(email_address: "reviewer@example.com", password: "correct horse battery staple"), name: "Other", provider: "anthropic").last
    theirs, = call_tool("list_tasks", {}, other)
    expect(theirs["content_reviews_for_you"]).to be_positive
  end

  it "can be asked for claims a model actually scores" do
    forecast = create_claim(curator, "Yang-Mills will be the next problem to fall.", type: "FORECAST")
    checkable, = curated_claim("Remote work raised measured output in the trial.")
    Tasks::Create.call(task_type: "QUALIFIER_CHECK", target: forecast)
    Tasks::Create.call(task_type: "QUALIFIER_CHECK", target: checkable)

    data, err = call_tool("next_task", { "settleable" => true })
    expect(err).to be(false)
    expect(data["available"]).to be(true)
    expect(data.dig("target", "claim_id")).to eq(checkable.id), "a FORECAST can never leave NOT_APPLICABLE"

    schema = Mcp::Server::TOOLS.find { |t| t[:name] == "next_task" }[:inputSchema]
    expect(schema[:properties]).to have_key(:settleable), "a lever an assistant cannot discover is not a lever"
  end

  # Two EVIDENCE_VERIFICATION tasks were worked before the ceiling became clear,
  # and real web searches were spent on claims carrying no probability at all
  # (docs/experiments/2026-09-20-second-connector-run.md).
  it "says what answering a task can and cannot change, before the work" do
    forecast = create_claim(curator, "Yang-Mills will fall next.", type: "FORECAST")
    Tasks::Create.call(task_type: "QUALIFIER_CHECK", target: forecast)
    data, err = call_tool("next_task", { "claim_id" => forecast.id })
    expect(err).to be(false), data.inspect
    expect(data["moves"]).to include("no probability"), "an unscoreable target should say so up front"
    expect(data["moves"]).to include("correct the type"), "and say what is still worth doing"

    claim, = curated_claim("Remote work raised measured output in the trial.")
    Tasks::Create.call(task_type: "OPPOSING_EVIDENCE_SEARCH", target: claim)
    found, = call_tool("next_task", { "claim_id" => claim.id, "types" => [ "OPPOSING_EVIDENCE_SEARCH" ] })
    expect(found["moves"]).to include("NONE_FOUND"), "a null search is a result and the packet should say so"

    schema = Mcp::Server::TOOLS.find { |t| t[:name] == "next_task" }[:outputSchema]
    expect(schema[:properties]).to have_key(:moves)
  end

  # moves said a null search "raises how well reviewed the claim is". True in
  # general, false for a lease on your own principal's claim, which is recorded
  # as self-performed and never moves coverage. Reported by the assistant that
  # read it and then watched coverage stay at 0.00 — the same failure this field
  # exists to prevent (docs/experiments/2026-09-20-second-connector-run.md).
  it "does not promise coverage on a check of your own principal's work" do
    recorded, = call_tool("record_investigation", { "claims" => [ { "handle" => "c", "text" => "My own claim about remote work.", "type" => "OBSERVATIONAL" } ] })
    own = recorded["claims"].first["id"]
    data, err = call_tool("next_task", { "claim_id" => own, "types" => [ "OPPOSING_EVIDENCE_SEARCH" ] })
    expect(err).to be(false), data.inspect
    expect(data["moves"]).to include("self-performed"), "whose work it is changes what answering can do"
    expect(data["moves"]).not_to include("raises how well reviewed")
  end

  # A thread on the claim reached only opposing-evidence packets, so an assistant
  # that worked verifications and qualifier checks never learned one existed and
  # walked past a source-lineage finding on the claim it was checking. It
  # reported that itself: the taxonomy was usable, the bridge from task work to
  # existing threads was missing.
  it "carries open threads on the claim into every kind of check" do
    claim, location, = curated_claim
    DeterminationThread.record!(subject: claim, concern: "Its two counted items may trace to one pollster.")
    %w[EVIDENCE_VERIFICATION QUALIFIER_CHECK OPPOSING_EVIDENCE_SEARCH].each do |type|
      Tasks::Create.call(task_type: type, target: claim, location: (location if type == "EVIDENCE_VERIFICATION"))
      packet = Task.where(task_type: type, target_id: claim.id).order(:created_at).last.packet
      threads = packet.dig("context", "threads")
      expect(threads).to be_present, "#{type} packet does not mention the thread"
      expect(threads["count"]).to eq(1)
      expect(threads["thread_ids"]).to be_present, "and it has to say which, or get_thread is a search"
      expect(threads["note"]).to include("get_thread")
      expect(threads["note"]).to include("never as a finding")
    end
  end

  # A null search left no trace: both submissions returned items: 0, and the
  # terms, the sources and the reasoning were discarded at the boundary. The
  # guidance said to say what you searched and the packet said to answer with an
  # empty answer, and there was no field that could hold the first (01a0c0d5).
  it "records what a null search covered, and says so where the result is read" do
    claim, = curated_claim("Remote work raised measured output in the trial.")
    Tasks::Create.call(task_type: "OPPOSING_EVIDENCE_SEARCH", target: claim)
    leased, = call_tool("next_task", { "claim_id" => claim.id, "types" => [ "OPPOSING_EVIDENCE_SEARCH" ] })
    expect(leased["answer_with"]).to include("searched"), "the packet has to name the field it asks you to fill"

    covered = "Searched \"fiduciary wedge\" against Ismail and Shelton by name, the concept phrasing, and the OpenExO material. Only unrelated legal commentary came back."
    data, err = call_tool("submit_task", { task_id: leased["task_id"], outcome: "NONE_FOUND", answer: {}, searched: covered })
    expect(err).to be(false), data.inspect
    expect(data["items"]).to eq(0), "a null still records no ops; the coverage is what was missing"

    payload = Contribution.find(data["contribution_id"]).payload
    expect(payload["searched"]).to eq(covered)
    expect(payload["outcome"]).to eq("NONE_FOUND")

    # Covered by the payload hash the signature is taken over, so the null is
    # auditable rather than asserted: changing a word invalidates the record.
    contribution = Contribution.find(data["contribution_id"])
    expect(Crypto::Hashing.json(payload)).to eq(contribution.payload_hash)
    expect(Crypto::Hashing.json(payload.merge("searched" => "#{covered}."))).not_to eq(contribution.payload_hash)

    # Blind until every slot is in, so the coverage appears with the result and
    # not before it.
    get "/tasks/#{leased['task_id']}"
    expect(response.body).not_to include("fiduciary wedge") if Task.find(leased["task_id"]).open_slots.positive?
  end

  it "clips an over-long description of a search rather than refusing the result" do
    claim, = curated_claim("Remote work raised measured output in the trial.")
    Tasks::Create.call(task_type: "OPPOSING_EVIDENCE_SEARCH", target: claim)
    leased, = call_tool("next_task", { "claim_id" => claim.id, "types" => [ "OPPOSING_EVIDENCE_SEARCH" ] })
    data, err = call_tool("submit_task", { task_id: leased["task_id"], outcome: "NONE_FOUND", answer: {},
                                           searched: "x" * (Tasks::Answer::SEARCH_NOTE_MAX + 500) })
    expect(err).to be(false), data.inspect
    expect(Contribution.find(data["contribution_id"]).payload["searched"].length).to eq(Tasks::Answer::SEARCH_NOTE_MAX)
    expect(data["note"]).to include("clipped"), "a caller told its prose was too long by an exception has lost the prose"
  end

  # Asked about one claim after answering it, and told a general truth about the
  # queue. The specific fact — you answered this, a principal answers once, so
  # nothing can be added to that answer now — is what the caller needed, and it
  # is what a maintainer wrongly told an assistant it could work around.
  it "says why a claim you have already answered has nothing left for you" do
    recorded, = call_tool("record_investigation", { "claims" => [ { "handle" => "c", "text" => "My own claim about remote work.", "type" => "OBSERVATIONAL" } ] })
    own = recorded["claims"].first["id"]
    leased, = call_tool("next_task", { "claim_id" => own, "types" => [ "OPPOSING_EVIDENCE_SEARCH" ] })
    call_tool("submit_task", { task_id: leased["task_id"], outcome: "NONE_FOUND", answer: {}, searched: "Looked everywhere obvious." })

    again, err = call_tool("next_task", { "claim_id" => own, "types" => [ "OPPOSING_EVIDENCE_SEARCH" ] })
    expect(err).to be(false)
    expect(again["available"]).to be(false)
    expect(again["reason"]).to include("already answered every open task on this claim")
    expect(again["reason"]).to include("Nothing can be added to a result by leasing its task again")
    expect(again["reason"]).not_to include("daily lease limit"), "the caller asked about one claim, not the queue"
  end

  # The task type is named for the usual case, but BuildContext picks the
  # direction per claim: a claim nothing yet supports is sent looking FOR
  # evidence. `moves` said "against" either way, so a worker was told the
  # opposite of what it had been asked for, in the field whose only job is to
  # say what the work can achieve before the effort is spent (01a0c0d5).
  it "names the direction the search actually asks for" do
    claim, = curated_claim("Remote work raised measured output in the trial.")
    Tasks::Create.call(task_type: "OPPOSING_EVIDENCE_SEARCH", target: claim)
    supported, = call_tool("next_task", { "claim_id" => claim.id, "types" => [ "OPPOSING_EVIDENCE_SEARCH" ] })
    direction = supported.dig("context", "search_direction")
    expect(supported["moves"]).to include(direction == "SUPPORT" ? "search FOR it" : "search AGAINST it")
    expect(supported["moves"]).to include(direction == "SUPPORT" ? "evidence for the claim" : "evidence against the claim")

    # And the bare claim the report was filed against: nothing counted, so the
    # search is for support, and the field must not say "against".
    bare = create_claim(curator, "A claim with nothing counted for it yet.", type: "OBSERVATIONAL")
    Tasks::Create.call(task_type: "OPPOSING_EVIDENCE_SEARCH", target: bare)
    data, err = call_tool("next_task", { "claim_id" => bare.id, "types" => [ "OPPOSING_EVIDENCE_SEARCH" ] })
    expect(err).to be(false), data.inspect
    expect(data.dig("context", "search_direction")).to eq("SUPPORT")
    expect(data["moves"]).to include("search FOR it")
    expect(data["moves"]).not_to include("evidence against the claim")
  end

  it "lists tasks in a bounded number of statements, and suggests only work this caller can take" do
    claim, = curated_claim
    12.times { |i| Tasks::Create.call(task_type: "QUALIFIER_CHECK", target: create_claim(curator, "Spare claim #{i} about productivity.", type: "CAUSAL")) }
    Tasks::Create.call(task_type: "OPPOSING_EVIDENCE_SEARCH", target: claim)

    used = statements { call_tool("list_tasks", { "limit" => 5 }) }
    expect(used).to be <= 25, "#{used} statements for a listing; it was ~3 per task plus a Section each"

    # Lease one, and it should stop being suggested to the caller holding it,
    # the way Tasks::Lease.candidates already refuses to hand it over twice.
    before, = call_tool("list_tasks", { "limit" => 20 })
    leased, err = call_tool("next_task", {})
    expect(err).to be(false)
    data, = call_tool("list_tasks", { "limit" => 20 })
    expect(data["next"].map { |t| t["task_id"] }).not_to include(leased["task_id"])

    # Two numbers that answer two different questions. The queue's total does
    # not move, because nobody has answered anything yet; the caller's does,
    # because there is one fewer task left for it to take.
    expect(data["open_for_you"]).to eq(before["open_for_you"] - 1)
  end

  # The 742 that stayed 742. A task wanting three independent answers keeps its
  # slot after the first, so the queue total is right not to move — and a caller
  # who has just answered a hundred of them reads that as having achieved
  # nothing. The two questions need two numbers.
  it "shows a caller's own remaining work falling while the queue total holds" do
    claim, = curated_claim
    3.times do |i|
      Tasks::Create.call(task_type: "QUALIFIER_CHECK", required_assignments: Audits::Policy.independent_checks,
                         target: create_claim(curator, "Spare claim #{i} about productivity.", type: "CAUSAL"))
    end
    Tasks::Create.call(task_type: "OPPOSING_EVIDENCE_SEARCH", target: claim)
    before, = call_tool("list_tasks", {})

    leased, err = call_tool("next_task", { types: [ "QUALIFIER_CHECK" ] })
    expect(err).to be(false)
    _, err = call_tool("submit_task", { task_id: leased["task_id"], outcome: "NONE_MATERIAL", answer: {} })
    expect(err).to be(false)

    data, = call_tool("list_tasks", {})
    expect(data["open"]).to eq(before["open"]), "two more answers are still wanted, so the queue is unchanged"
    expect(data["open_for_you"]).to eq(before["open_for_you"] - 1), "but there is one fewer left for this caller"
    expect(data["answers_wanted"]).to eq(before["answers_wanted"] - 1)
    expect(data["answers_wanted_for_you"]).to eq(before["answers_wanted_for_you"] - 3), "all three of that task's answers are now beyond this caller"
  end

  # An anonymous caller has taken nothing, so the two numbers agree — and that
  # is the honest answer rather than a missing field.
  it "gives a caller with nothing of its own the same number twice" do
    Tasks::Create.call(task_type: "QUALIFIER_CHECK", target: curated_claim.first)
    data, err = call_tool("list_tasks", {}, nil)
    expect(err).to be(false)
    expect(data["open_for_you"]).to eq(data["open"])
    expect(data["answers_wanted_for_you"]).to eq(data["answers_wanted"])
  end

  # A curator's claim with one direct support: a claim someone else recorded.
  def curated_claim(text = "Remote work raises productivity.")
    source = create_source(curator, content: "Employees who worked remotely reported higher productivity in the survey.")
    location = create_location(curator, source, start: 0, finish: 40)
    claim = create_claim(curator, text, type: "CAUSAL")
    link = link_evidence(curator, create_evidence(curator, location, statement: "The survey reports higher productivity."), claim)
    [ claim, location, link ]
  end

  def a_source(handle = "s")
    { "handle" => handle, "type" => "WEBSITE", "title" => "A contrary study", "url" => "https://example.test/contrary", "retrieved_at" => Time.now.utc.iso8601 }
  end

  it "leases an opposing search and a verification, answers both in the record vocabulary, and the results count (#1)" do
    claim, location, = curated_claim
    Tasks::Create.call(task_type: "OPPOSING_EVIDENCE_SEARCH", target: claim)
    Tasks::Create.call(task_type: "EVIDENCE_VERIFICATION", target: claim, location: location)
    before = Scoring::Score.call(claim, Contribution.maximum(:seq), model).probability

    data, err = call_tool("next_task", { types: [ "OPPOSING_EVIDENCE_SEARCH" ] })
    expect(err).to be(false)
    expect(data).to include("available" => true, "task_type" => "OPPOSING_EVIDENCE_SEARCH")
    expect(data["target"]).to include("claim_id" => claim.id, "url" => "http://www.example.com/claims/#{claim.id}")
    expect(data["context"]["search_direction"]).to eq("CONTRADICT")
    expect(data["answer_with"]).to include("NONE_FOUND")
    expect(data["outcomes"]).to include("FOUND")

    # The caps were in the stored packet and not in what the assistant is handed,
    # so the only way to learn one was to exceed it and be refused. They are named
    # here the way the rejection names them: TOO_MANY_OPS reads max_ops, and
    # OP_NOT_ALLOWED reads allowed_ops.
    expect(data["constraints"]).to include(
      "max_ops" => Tasks::Types.spec("OPPOSING_EVIDENCE_SEARCH")[:max_ops],
      "allowed_ops" => Tasks::Types.spec("OPPOSING_EVIDENCE_SEARCH")[:allowed_ops]
    )
    expect(data).not_to have_key("max_items"), "one number, one name (canonical vocabulary)"
    schema = Mcp::Server::TOOLS.find { |t| t[:name] == "next_task" }[:outputSchema]
    expect(schema[:properties]).to have_key(:constraints), "a field an assistant must read cannot be undeclared"

    answer = { "sources" => [ a_source ], "excerpts" => [ { "handle" => "x", "source" => "s", "text" => "Remote workers reported lower productivity." } ],
               "evidence" => [ { "handle" => "e", "excerpt" => "x", "statement" => "The study reports lower productivity for remote workers." } ],
               "links" => [ { "evidence" => "e", "claim" => "target", "direction" => "CONTRADICT", "strength" => "MODERATE", "steps" => 1 } ] }
    data, err = call_tool("submit_task", { task_id: data["task_id"], outcome: "FOUND", answer: answer })
    expect(err).to be(false)
    expect(data).to include("accepted" => true, "status" => "ACCEPTED", "items" => 4)
    expect(data["note"]).to include("Counted now")
    result = Contribution.find(data["contribution_id"])
    expect(result).to have_attributes(action_type: "TASK_RESULT", custody: "SERVER", task_id: Task.find_by(task_type: "OPPOSING_EVIDENCE_SEARCH").id)
    source = Source.where(contribution_id: result.id).first
    expect(source).to have_attributes(retrieval_pending: true, content: nil, canonical_uri: "https://example.test/contrary")
    expect(EvidenceClaimLink.where(contribution_id: result.id).first.direction).to eq("CONTRADICT")
    expect(Scoring::Score.call(claim, Contribution.maximum(:seq), model).probability).not_to eq(before)
    expect(data.dig("claim", "id")).to eq(claim.id)

    data, = call_tool("next_task", { types: [ "EVIDENCE_VERIFICATION" ] })
    expect(data["context"]).to include("source_location_id" => location.id)
    expect(data["context"]["untrusted_excerpt"]).to include("remotely")
    data, err = call_tool("submit_task", { task_id: data["task_id"], outcome: "CONFIRMED",
                                           answer: { "evidence" => [ { "handle" => "e", "excerpt" => "packet", "statement" => "The passage reports higher productivity." } ],
                                                     "links" => [ { "evidence" => "e", "claim" => "target", "direction" => "SUPPORT" } ] } })
    expect(err).to be(false)
    expect(data["accepted"]).to be(true)
    expect(EvidenceItem.find_by(contribution_id: data["contribution_id"]).source_location_id).to eq(location.id)
  end

  it "accepts a qualifier answer with a narrower claim and holds a supersession of another principal's link as a proposal (#2)" do
    claim, location, link = curated_claim
    Tasks::Create.call(task_type: "QUALIFIER_CHECK", target: claim)
    data, = call_tool("next_task", {})
    expect(data["context"]["counted_links"].first).to include("link_id" => link.id, "source_location_id" => location.id)

    answer = { "claims" => [ { "handle" => "n", "text" => "Remote work raised self-reported productivity among surveyed employees.", "type" => "QUANTITATIVE" } ],
               "edges" => [ { "from" => "n", "to" => "target", "type" => "NARROWS" } ],
               "evidence" => [ { "handle" => "e", "excerpt" => location.id, "statement" => "The survey measured self-reports, not output." } ],
               "links" => [ { "evidence" => "e", "claim" => "target", "direction" => "QUALIFY", "steps" => 1 } ] }
    data, err = call_tool("submit_task", { task_id: data["task_id"], outcome: "QUALIFIERS_FOUND", answer: answer })
    expect(err).to be(false), data.inspect
    expect(data["accepted"]).to be(true)
    expect(ClaimEdge.find_by(to_claim_id: claim.id).relationship_type).to eq("NARROWS")

    other, _, other_link = curated_claim("Remote work lowers costs.")
    Tasks::Create.call(task_type: "QUALIFIER_CHECK", target: other)
    data, = call_tool("next_task", { claim_id: other.id })
    data, err = call_tool("submit_task", { task_id: data["task_id"], outcome: "QUALIFIERS_FOUND",
                                           answer: { "supersede" => [ { "link_id" => other_link.id, "direction" => "SUPPORT", "strength" => "WEAK", "steps" => 2, "reason" => "population omitted" } ] } })
    expect(err).to be(false)
    expect(data).to include("accepted" => false, "status" => "PENDING")
    expect(data["note"]).to include("different principal")
  end

  # Stage 34. This used to assert that a principal was never handed any task on
  # its own claim, which is broader than 04 §3.1 asks and left a person who
  # outlined a source alone unable to finish checking it. The routine checks that
  # open alongside a recording are now leasable by their author and recorded as
  # self-performed; an explicitly requested blind check is not.
  it "hands an assistant its own claim's routine checks, marked self-performed, and list_tasks needs no token (#3)" do
    bundle = { "claims" => [ { "handle" => "c", "text" => "My own claim about the weather.", "type" => "OBSERVATIONAL" } ] }
    data, = call_tool("record_investigation", bundle)
    own = data["claims"].first["id"]
    expect(Task.where(target_id: own, status: "OPEN").count).to eq(2)

    data, err = call_tool("list_tasks", {}, nil)
    expect(err).to be(false)
    expect(data["open"]).to eq(Task.where(status: "OPEN").count)
    expect(data["by_type"]).to include("OPPOSING_EVIDENCE_SEARCH" => 1, "QUALIFIER_CHECK" => 1)
    expect(data["next"].first["target"]["claim_id"]).to eq(own)
    expect(data["how"]).to include("work N open tasks")

    data, err = call_tool("next_task", { claim_id: own })
    expect(err).to be(false)
    expect(data["available"]).to be(true), "a person must be able to finish their own investigation"
    assignment = TaskAssignment.find_by!(task_id: data["task_id"])
    expect(assignment.self_performed).to be(true), "and it must be recorded as their own work"
    expect(Tasks::Lease::SELF_CHECKABLE).to include(Task.find(data["task_id"]).task_type)
  end

  it "still refuses a blind check its own principal asked for, and the types reserved for another reader (#3)" do
    bundle = { "claims" => [ { "handle" => "c", "text" => "Another claim of my own.", "type" => "OBSERVATIONAL" } ] }
    data, = call_tool("record_investigation", bundle)
    own = data["claims"].first["id"]
    Task.where(target_id: own).delete_all

    # Asked for deliberately, so the asker does not answer it (Stage 19).
    out, err = call_tool("open_task", { claim_id: own, type: "QUALIFIER_CHECK" })
    expect(err).to be(false)
    expect(Task.find(out["task_id"]).blind_requested).to be(true)
    data, err = call_tool("next_task", { claim_id: own })
    expect(err).to be(false)
    expect(data["available"]).to be(false)

    # Independence grouping is a structural judgement about one's own reasoning.
    Task.where(target_id: own).delete_all
    Tasks::Create.call(task_type: "SOURCE_INDEPENDENCE_CHECK", target: Claim.find(own))
    expect(Tasks::Lease::SELF_CHECKABLE).not_to include("SOURCE_INDEPENDENCE_CHECK")
    data, err = call_tool("next_task", { claim_id: own })
    expect(err).to be(false)
    expect(data["available"]).to be(false)
  end

  it "refuses an expired lease, a wrong outcome, and a disallowed item, and releases a lease (#4)" do
    claim, location, = curated_claim
    Tasks::Create.call(task_type: "EVIDENCE_VERIFICATION", target: claim, location: location)
    data, = call_tool("next_task", {})
    task = Task.find(data["task_id"])

    data, err = call_tool("submit_task", { task_id: task.id, outcome: "MAYBE", answer: {} })
    expect(err).to be(true)
    expect(errors_of(data)).to include("SCHEMA_INVALID")

    data, err = call_tool("submit_task", { task_id: task.id, outcome: "CONFIRMED", answer: { "sources" => [ a_source ] } })
    expect(err).to be(true)
    expect(errors_of(data)).to include("OP_NOT_ALLOWED")

    task.assignments.first.update_column(:lease_expires_at, 1.minute.ago)
    data, err = call_tool("submit_task", { task_id: task.id, outcome: "CANNOT_DETERMINE", answer: {} })
    expect(err).to be(true)
    expect(errors_of(data)).to include("LEASE_EXPIRED").or include("LEASE_NOT_ACTIVE")
    expect(Contribution.where(action_type: "TASK_RESULT")).to be_empty

    Tasks::Lease.expire_stale!
    data, = call_tool("next_task", {})
    expect(data["available"]).to be(true)
    data, err = call_tool("release_task", { task_id: task.id })
    expect(err).to be(false)
    expect(data["status"]).to eq("RELEASED")
    expect(task.reload.status).to eq("OPEN")
  end

  it "refuses read-only grants and anonymous assistants on leasing, and leaves goldens and replay alone (#5)" do
    claim, = curated_claim
    Tasks::Create.call(task_type: "OPPOSING_EVIDENCE_SEARCH", target: claim)

    data, err = call_tool("next_task", {}, nil)
    expect(err).to be(true)
    expect(errors_of(data)).to include("TOKEN_INVALID")
    expect(data["errors"].first["detail"]).to include("connect under a name")

    record = AssistantToken.find_by(token_digest: AssistantToken.digest(token))
    status, body = Mcp::Server.new(token: record, base_url: "http://www.example.com", read_only: true)
                              .handle({ "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call", "params" => { "name" => "next_task", "arguments" => {} } })
    expect(status).to eq(200)
    expect(body.dig(:result, :structuredContent, :errors).first[:code]).to eq("INSUFFICIENT_SCOPE")
    expect(TaskAssignment.count).to eq(0)

    data, err = call_tool("submit_task", { task_id: Task.first.id, outcome: "NONE_FOUND", answer: {} })
    expect(err).to be(true)
    expect(errors_of(data)).to include("LEASE_MISSING")

    before = Ledger::TableDigest.projections
    Ledger::Replay.call
    expect(Ledger::TableDigest.projections).to eq(before)
  end

  # Stage 34, and the safety property the whole stage rests on: a person may
  # finish checking their own investigation, and doing so must not move the
  # number that means somebody else has looked.
  it "records a self-check without raising review coverage (#3)" do
    bundle = { "claims" => [ { "handle" => "c", "text" => "My own claim about rainfall.", "type" => "OBSERVATIONAL" } ] }
    data, = call_tool("record_investigation", bundle)
    claim = Claim.find(data["claims"].first["id"])
    before = Scoring::Score.call(claim, Contribution.maximum(:seq), model).review_coverage

    leased, err = call_tool("next_task", { claim_id: claim.id })
    expect(err).to be(false)
    expect(leased["available"]).to be(true)
    task = Task.find(leased["task_id"])
    expect(Tasks::Lease::SELF_CHECKABLE).to include(task.task_type)

    outcome = task.task_type == "OPPOSING_EVIDENCE_SEARCH" ? "NONE_FOUND" : "NONE_MATERIAL"
    _, err = call_tool("submit_task", { task_id: task.id, outcome: outcome, answer: {} })
    expect(err).to be(false)

    assignment = TaskAssignment.find_by!(task_id: task.id)
    expect(assignment.self_performed).to be(true)
    expect(assignment.result_contribution_id).to be_present

    seq = Contribution.maximum(:seq)
    expect(Scoring::Score.call(claim, seq, model).review_coverage).to eq(before),
      "a check by the claim's own author must not raise review coverage"
    expect(Tasks::Checks.for(claim.id, seq)).to be_empty,
      "and must never reach the scorer's task_checks at all"
    expect(Tasks::Checks.self_for(claim.id, seq).values.sum).to eq(1),
      "but it is recorded, and reportable"
  end

  # Found in a live run. self_for and the share-line split both counted through
  # Tasks::Checks::CHECK_FOR, which maps task types to checklist item names.
  # EVIDENCE_VERIFICATION is not a checklist item — it contributes evidence links
  # — so the most numerous check type was invisible to the figures built to
  # report it: a self-check was recorded correctly and counted as nothing.
  it "counts an evidence verification self-check, which is not a checklist item (#3)" do
    claim, location, = curated_claim
    task = Tasks::Create.call(task_type: "EVIDENCE_VERIFICATION", target: claim, location: location)
    record = AssistantToken.find_by_token(token)
    assignment = TaskAssignment.create!(task: task, contributor: record.agent, principal: record.principal,
                                        lease_expires_at: 1.hour.from_now, status: "LEASED", self_performed: true)
    _, err = call_tool("submit_task", { task_id: task.id, outcome: "CONFIRMED", answer: {} })
    expect(err).to be(false)

    seq = Contribution.maximum(:seq)
    expect(Tasks::Checks::CHECK_FOR).not_to have_key("EVIDENCE_VERIFICATION"), "this is why it was missed"
    expect(assignment.reload.result_contribution_id).to be_present
    expect(Tasks::Checks.self_for(claim.id, seq)).to eq({ "EVIDENCE_VERIFICATION" => 1 })
    expect(Tasks::Checks.for(claim.id, seq)).to be_empty, "and it still must not reach the scorer"
  end
  # Reported from a live run: next_task kept handing out checks on a claim that
  # had been merged. submit_task refuses those with CLAIM_NOT_CURRENT, and
  # releasing one put it straight back at the head of the queue — the same
  # unworkable task arrived three times and blocked the filter behind it.
  it "cancels a check whose claim has been merged away instead of handing it out (#3)" do
    claim, location, = curated_claim("A claim that will be merged away.")
    survivor, = curated_claim("The claim it merges into.")
    task = Tasks::Create.call(task_type: "EVIDENCE_VERIFICATION", target: claim, location: location)
    expect(task.status).to eq("OPEN")

    append(action_type: "MERGE_CLAIMS", key_pair: curator,
           payload: { "from_claim_id" => claim.id, "into_claim_id" => survivor.id, "reason" => "same proposition" })
    seq = Contribution.maximum(:seq)
    expect(Claim.find(claim.id).current_at?(seq)).to be(false)

    data, err = call_tool("next_task", { claim_id: claim.id })
    expect(err).to be(false)
    expect(data["available"]).to be(false), "an unworkable task must not be leased"
    expect(task.reload.status).to eq("CANCELLED")
    expect(task.cancelled_reason).to eq(Tasks::Lease::TARGET_NOT_CURRENT)
  end
end
