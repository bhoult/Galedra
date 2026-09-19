require "rails_helper"

RSpec.describe "Inferences: recorded reasoning steps (Stage 25)", type: :request do
  include LedgerHelpers
  include GraphHelpers
  before { release_models }

  let(:password) { "correct horse battery staple" }
  let(:author) { Assistants::Connect.call(user: User.create!(email_address: "a@example.com", password: password), name: "A", provider: "anthropic").last }
  let(:reviewer) { Assistants::Connect.call(user: User.create!(email_address: "r@example.com", password: password), name: "R", provider: "openai").last }

  def call_tool(name, arguments, tok)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{tok}" }
    body = response.parsed_body
    [ body.dig("result", "structuredContent"), body.dig("result", "isError") ]
  end

  it "records a step with four premises and one failing, projects premises and edges, marks the weakest premise, and leaves scores unchanged (#1, #3)" do
    pair, = register_key
    a = create_claim(pair, "The bill passed the House.")
    b = create_claim(pair, "The bill passed the Senate.")
    c = create_claim(pair, "The president signed the bill.")
    d = create_claim(pair, "A court has enjoined the law.")
    e = create_claim(pair, "The law is in force.")
    source = create_source(pair)
    location = create_location(pair, source)
    link_evidence(pair, create_evidence(pair, location, statement: "The record shows the House passed it."), a)
    link_evidence(pair, create_evidence(pair, location, statement: "The record shows a court enjoined it."), d)
    seq = Contribution.maximum(:seq)
    model = Scoring::Registry.default_model
    snapshot = ->(cl, s) { r = Scoring::Score.call(cl, s, model); [ r.assessment_state, r.probability, r.review_checklist, r.support_groups, r.contradict_groups ] }
    before = %w[a b c d e].zip([ a, b, c, d, e ]).to_h { |k, cl| [ k, snapshot.call(cl, seq) ] }

    payload = { "conclusion_claim_id" => e.id, "premises" => [ { "claim_id" => a.id, "polarity" => "HOLDS" }, { "claim_id" => b.id, "polarity" => "HOLDS" }, { "claim_id" => c.id, "polarity" => "HOLDS" }, { "claim_id" => d.id, "polarity" => "FAILS" } ],
                "inference_type" => "DEDUCTIVE", "rule" => "A bill passed by both houses and signed is law unless a court enjoins it.", "strength" => "ENTAILS", "affirms_not_private_individual" => true }
    result = append(action_type: "CREATE_INFERENCE", key_pair: pair, payload: payload)
    inference = Inference.find(Ledger::Ids.derive(result.contribution.id, "inference"))
    expect(inference).to be_accepted
    expect(inference.premises.count).to eq(4)
    expect(ClaimEdge.where(from_claim_id: e.id, relationship_type: "DERIVED_FROM").count).to eq(4)

    after_seq = Contribution.maximum(:seq)
    %w[a b c d e].zip([ a, b, c, d, e ]).each { |k, cl| expect(snapshot.call(cl, after_seq)).to eq(before[k]) }
    expect(Scoring::Score.call(e, after_seq, model).trace.to_json).not_to include(inference.id)

    view = Inferences::View.for_claim(e, after_seq, model)
    step = view[:concluded_from].first
    expect(step[:premises].map { |p| p[:polarity] }).to eq(%w[HOLDS HOLDS HOLDS FAILS])
    expect(step[:weakest_premise_id]).to eq(step[:premises].last[:id]) # D reads supported but must fail
    expect(Inferences::View.for_claim(d, after_seq, model)[:premise_in].first[:id]).to eq(inference.id)

    get "/claims/#{e.id}"
    expect(response.body).to include('id="inferences"').and include("weakest premise").and include(Inference::NOTE)
    get "/claims/#{d.id}"
    expect(response.body).to include("Used as a premise in").and include("fails: ")
    get "/api/v1/inferences/#{inference.id}"
    expect(response.parsed_body.dig("inference", "premises").size).to eq(4)
    get "/api/v1/claims/#{e.id}"
    expect(response.parsed_body.dig("claim", "inferences", "concluded_from").size).to eq(1)

    before_digest = Ledger::TableDigest.projections
    Ledger::Replay.call
    expect(Ledger::TableDigest.projections).to eq(before_digest)
    expect(Ledger::Verify.call).to be_ok
  end

  it "refuses bad shapes and records cycles (#2)" do
    pair, = register_key
    a = create_claim(pair, "A.")
    b = create_claim(pair, "B.")
    c = create_claim(pair, "C.")
    base = { "inference_type" => "DEDUCTIVE", "affirms_not_private_individual" => true }
    make = ->(extra) { append(action_type: "CREATE_INFERENCE", key_pair: pair, payload: base.merge(extra)) }
    expect_rejected("SCHEMA_INVALID") { make.call("conclusion_claim_id" => a.id, "premises" => [ { "claim_id" => a.id, "polarity" => "HOLDS" }, { "claim_id" => b.id, "polarity" => "HOLDS" } ]) }
    expect_rejected("SCHEMA_INVALID") { make.call("conclusion_claim_id" => c.id, "premises" => [ { "claim_id" => a.id, "polarity" => "HOLDS" }, { "claim_id" => a.id, "polarity" => "HOLDS" } ]) }
    expect_rejected("SCHEMA_INVALID") { make.call("conclusion_claim_id" => c.id, "premises" => [ { "claim_id" => a.id, "polarity" => "HOLDS" } ]) }
    expect_rejected("SCHEMA_INVALID") { make.call("conclusion_claim_id" => c.id, "premises" => Array.new(13) { { "claim_id" => a.id, "polarity" => "HOLDS" } }) }
    expect_rejected("SCHEMA_INVALID") { make.call("conclusion_claim_id" => c.id, "premises" => [ { "claim_id" => a.id, "polarity" => "HOLDS" }, { "claim_id" => b.id, "polarity" => "HOLDS" } ], "inference_type" => "MAGIC") }
    expect_rejected("SCHEMA_INVALID") { make.call("conclusion_claim_id" => c.id, "premises" => [ { "claim_id" => a.id, "polarity" => "HOLDS" }, { "claim_id" => b.id, "polarity" => "HOLDS" } ], "strength" => "PROVES") }
    make.call("conclusion_claim_id" => c.id, "premises" => [ { "claim_id" => a.id, "polarity" => "HOLDS" }, { "claim_id" => b.id, "polarity" => "HOLDS" } ])
    make.call("conclusion_claim_id" => a.id, "premises" => [ { "claim_id" => c.id, "polarity" => "HOLDS" }, { "claim_id" => b.id, "polarity" => "HOLDS" } ])
    expect(Inference.count).to eq(2)
  end

  it "opens a review task on a recorded inference; a different principal answers MISSING_PREMISE with a new claim and a corrected step (#4); strained steps show on the weaknesses page" do
    pair, = register_key
    a = create_claim(pair, "It rained overnight.")
    b = create_claim(pair, "The street is wet.")
    c = create_claim(pair, "The sprinklers ran.")
    data, err = call_tool("record_inference", { conclusion_claim_id: b.id, premises: [ { claim: a.id }, { claim: c.id, polarity: "FAILS" } ], type: "CAUSAL", rule: "Rain wets streets." }, author)
    expect(err).to be(false), data.inspect
    task = Task.find_by(task_type: "INFERENCE_REVIEW", target_id: data["inference_id"])
    expect(task).to be_present
    expect(task.target).to be_a(Inference)

    mine, = call_tool("next_task", { types: [ "INFERENCE_REVIEW" ] }, author)
    expect(mine["available"]).to be(false)
    packet, err = call_tool("next_task", { types: [ "INFERENCE_REVIEW" ] }, reviewer)
    expect(err).to be(false), packet.inspect
    expect(packet["context"]["premises"].size).to eq(2)
    expect(packet["target"]["url"]).to include("#inferences")
    answer = { claims: [ { handle: "m", text: "No street cleaner passed.", type: "OBSERVATIONAL" } ],
               inferences: [ { handle: "fixed", conclusion: "target", premises: [ { claim: a.id }, { claim: c.id, polarity: "FAILS" }, { claim: "m" } ], type: "CAUSAL", rule: "Rain wets streets unless something dried them." } ] }
    data, err = call_tool("submit_task", { task_id: packet["task_id"], outcome: "MISSING_PREMISE", answer: answer }, reviewer)
    expect(err).to be(false), data.inspect
    expect(data["accepted"]).to be(true)
    expect(Inference.where(conclusion_claim_id: b.id).count).to eq(2)
    expect(Inference.order(:created_seq).last.premises.count).to eq(3)
    expect(Claim.find_by(canonical_text: "No street cleaner passed.")).to be_present

    # A strained step: conclusion supported, a HOLDS premise contradicted.
    source = create_source(pair)
    location = create_location(pair, source)
    link_evidence(pair, create_evidence(pair, location, statement: "The street is wet."), b)
    link_evidence(pair, create_evidence(pair, location, statement: "It did not rain."), a, direction: "CONTRADICT")
    get "/weaknesses"
    expect(response.body).to include("strained inferences (").and include("The street is wet.")
    expect(Inferences::View.strained(Contribution.maximum(:seq)).size).to be >= 1
  end
end
