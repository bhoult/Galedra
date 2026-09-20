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

  it "lists tasks in a bounded number of statements, and suggests only work this caller can take" do
    claim, = curated_claim
    12.times { |i| Tasks::Create.call(task_type: "QUALIFIER_CHECK", target: create_claim(curator, "Spare claim #{i} about productivity.", type: "CAUSAL")) }
    Tasks::Create.call(task_type: "OPPOSING_EVIDENCE_SEARCH", target: claim)

    used = statements { call_tool("list_tasks", { "limit" => 5 }) }
    expect(used).to be <= 25, "#{used} statements for a listing; it was ~3 per task plus a Section each"

    # Lease one, and it should stop being suggested to the caller holding it,
    # the way Tasks::Lease.candidates already refuses to hand it over twice.
    leased, err = call_tool("next_task", {})
    expect(err).to be(false)
    data, = call_tool("list_tasks", { "limit" => 20 })
    expect(data["next"].map { |t| t["task_id"] }).not_to include(leased["task_id"])
    expect(data["open"]).to be_positive, "the totals stay objective: they describe the outline, not the caller"
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
