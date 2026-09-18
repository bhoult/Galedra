require "rails_helper"

RSpec.describe "Answer cards, why, summaries, and weaknesses (07 Phase 6 #1, #2; scenarios E, H)", type: :request do
  before { release_models }

  let(:model) { Scoring::Registry.default_model }

  it "renders the public demo's compact answers at S5 (08 §9): state, main issue, and cites" do
    graph = build_public_demo
    seq = graph.checkpoints["S5"]
    h = graph.handles
    c2 = graph.claims["C2"]

    card = Cards::ClaimCard.call(c2, seq, model)
    expect(card).to include(headline: "Unresolved", independent_lineages: 1, review_checks: "3 of 4", stability: "MEDIUM")
    expect(card[:main_issue]).to include(kind: "QUALIFY_LINK", cites: [ h["E6"].id ])
    expect(card[:main_issue][:text]).to include("Acme customer accounts")
    expect(card[:related]).to include(a_hash_including(claim_id: graph.claims["C3"].id, relation: "NARROWS", headline: "Supported"))

    summary = Summaries::Generate.call(c2, seq, model, type: "STANDARD")
    cites = summary[:sentences].flat_map { |s| s["cites"] }
    expect(cites).to include(h["E1"].id, h["G1"].id, h["E6"].id, graph.claims["C3"].id, "coverage:#{c2.id}")
    expect(summary[:sentences].first["text"]).to start_with("Unresolved.")
    expect(summary[:sentences].first["text"]).to include("400")
    expect(summary[:generator]).to eq("stub-v0.1")
    expect(summary[:sentences].size).to be <= 6
    expect(Summaries::Generate.call(c2, seq, model, type: "SHORT")[:sentences].size).to be <= 2

    c4 = graph.claims["C4"]
    c4_card = Cards::ClaimCard.call(c4, seq, model)
    expect(c4_card[:headline]).to eq("Leans contradicted")
    c4_summary = Summaries::Generate.call(c4, seq, model)
    c4_cites = c4_summary[:sentences].flat_map { |s| s["cites"] }
    expect(c4_cites).to include(h["E7"].id, h["T1"].id)
    expect(c4_cites.any? { |c| c.start_with?("audit:") }).to be(true)
    expect(c4_summary[:sentences].map { |s| s["text"] }.join(" ")).to include("rejected on audit").and include("found none")

    get "/api/v1/claims/#{graph.claims['C5'].id}"
    card5 = response.parsed_body["claim"]["card"]
    expect(card5["headline"]).to eq("Not assessed")
    expect(card5["reason"]).to include("value judgment")
    expect(response.parsed_body["claim"]["assessment"]["probability"]).to be_nil

    get "/api/v1/sources/#{h['SD'].id}"
    cards = response.parsed_body["cards"]
    expect(cards["cards"].map { |c| c["assessment_state"] }).to contain_exactly("UNRESOLVED", "LEANS_CONTRADICTED", "NOT_APPLICABLE", "UNRESOLVED")
    expect(cards["summary"]).to include("4 claims checked").and include("1 not scored")
    expect(cards["cards"].find { |c| c["claim_id"] == c4.id }["card"]["headline"]).to eq("Leans contradicted")
  end

  it "answers why with the strongest evidence, suppressed dependents, gaps, and the most moving addition" do
    graph = build_public_demo
    c2 = graph.claims["C2"]
    h = graph.handles
    get "/api/v1/claims/#{c2.id}/why", params: { snapshot_seq: graph.checkpoints["S1"] }
    why = response.parsed_body
    expect(why["strongest_support"]).to include("evidence" => h["E1"].id, "effective_weight" => "0.918000")
    expect(why["strongest_contradiction"]).to be_nil
    expect(why["suppressed_dependents"].map { |s| s["evidence"] }).to eq([ h["E2"].id ])
    expect(why["review_gaps"]).to include("opposing_search_done", "independence_reviewed")
    change = why["what_would_most_change_this"]
    expect(change).to include("direction" => "CONTRADICT", "state_from" => "SUPPORTED")
    expect(change["text"]).to include("contradicts")

    get "/api/v1/claims/#{graph.claims['C5'].id}/why"
    expect(response.parsed_body["what_would_most_change_this"]).to be_nil
  end

  it "rejects a generator that cites unknown ids and serves the stub (#1), and regenerates when the input changes (#2)" do
    curator, = register_key
    source = create_source(curator, type: "DATASET", content: "Survey: 62% of 400 respondents reported higher productivity.")
    evidence = create_evidence(curator, create_location(curator, source), observation: "DATASET_RESULT")
    claim = create_claim(curator, "62% of respondents reported higher productivity.", type: "QUANTITATIVE")
    link_evidence(curator, evidence, claim)
    seq = Contribution.maximum(:seq)

    bad = Class.new do
      def name = "bad-llm-v0"
      def summarize(_input, type:) = [ { "text" => "Everyone agrees this is true.", "cites" => [ "E999" ] } ]
    end.new
    served = Summaries::Generate.call(claim, seq, model, adapter: bad)
    expect(served[:generator]).to eq("stub-v0.1")
    expect(served[:sentences].first["cites"]).to eq([ evidence.id ])

    uncited = Class.new do
      def name = "uncited-llm-v0"
      def summarize(_input, type:) = [ { "text" => "Trust me.", "cites" => [] } ]
    end.new
    expect(Summaries::Generate.call(claim, seq, model, adapter: uncited)[:generator]).to eq("stub-v0.1")

    good = Class.new do
      def name = "good-llm-v0"
      def summarize(input, type:) = [ { "text" => "A survey supports it.", "cites" => [ input["kept"].first["evidence"] ] } ]
    end.new
    input_before = Summaries::Input.hash(Summaries::Input.build(claim, seq, model))
    fresh = Summaries::Generate.call(claim, seq, model, adapter: good)
    expect(fresh[:generator]).to eq("stub-v0.1")
    expect(fresh[:input_hash]).to eq(input_before)

    reviewer, = register_reviewer
    other = create_evidence(curator, create_location(curator, source), statement: "another")
    audit(reviewer, link_evidence(curator, other, claim, direction: "CONTRADICT", strength: "WEAK"))
    later = Contribution.maximum(:seq)
    expect(Summaries::Input.hash(Summaries::Input.build(claim, later, model))).not_to eq(input_before)
    regenerated = Summaries::Generate.call(claim, later, model, adapter: good)
    expect(regenerated[:generator]).to eq("good-llm-v0")
    expect([ evidence.id, other.id ]).to include(regenerated[:sentences].first["cites"].first)
    expect(Summary.where(claim_id: claim.id, snapshot_seq: later).count).to eq(1)

    get "/api/v1/claims/#{claim.id}/summary", params: { type: "short" }
    expect(response.parsed_body["summary_type"]).to eq("SHORT")
    get "/api/v1/claims/#{claim.id}/summary", params: { type: "LONG" }
    expect(response).to have_http_status(422)
  end

  it "lists the weaknesses, including a claim on which the two models disagree (scenario H)" do
    graph = build_public_demo
    get "/api/v1/weaknesses", params: { snapshot_seq: graph.checkpoints["S1"] }
    lists = response.parsed_body["lists"]
    expect(lists["models_disagree"].map { |e| e["claim_id"] }).to eq([ graph.claims["C6"].id ])
    expect(lists["models_disagree"].first["detail"]["states"]).to eq("ledger-default@0.1.0" => "UNRESOLVED", "ledger-strict@0.1.0" => "NOT_APPLICABLE")
    expect(lists["independence_unreviewed"].map { |e| e["claim_id"] }).to include(graph.claims["C2"].id)
    expect(lists["low_coverage_scored"].map { |e| e["claim_id"] }).to include(graph.claims["C2"].id)
    expect(lists["models_disagree"].first["what_would_most_change_this"]).to include("direction")

    get "/api/v1/weaknesses", params: { snapshot_seq: graph.checkpoints["S2"], kind: "provisional" }
    expect(response.parsed_body["lists"].keys).to eq([ "provisional" ])
    expect(response.parsed_body["lists"]["provisional"].map { |e| e["claim_id"] }).to include(graph.claims["C4"].id)
    get "/api/v1/weaknesses", params: { snapshot_seq: graph.checkpoints["S2"], kind: "contested" }
    expect(response.parsed_body["lists"]["contested"].map { |e| e["claim_id"] }).to eq([ graph.claims["C4"].id ])
    get "/api/v1/weaknesses", params: { kind: "bogus" }
    expect(response).to have_http_status(422)
  end

  it "extracts claim proposals deterministically from the memo, with types and an extra textual claim per citation" do
    memo = "Remote work boosts productivity: 62% of remote workers report higher productivity (Journal of Distributed Work Research, 2025). Companies should adopt remote work."
    proposals = Llm::Adapter.current.extract_claims(memo)
    texts = proposals.map { |p| [ p["canonical_text"], p["claim_type"] ] }
    expect(texts).to include([ "Remote work boosts productivity.", "CAUSAL" ], [ "62% of remote workers report higher productivity.", "QUANTITATIVE" ],
                             [ "Journal of Distributed Work Research (2025) reports that 62% of remote workers report higher productivity.", "TEXTUAL" ],
                             [ "Companies should adopt remote work.", "NORMATIVE" ])
    expect(proposals.first).to have_key("warnings")
    expect(Llm::Adapter.current.name).to eq("stub-v0.1")
    with_env("LEDGER_LLM_ADAPTER" => "gpt") { expect { Llm::Adapter.current }.to raise_error(ArgumentError) }
  end
end
