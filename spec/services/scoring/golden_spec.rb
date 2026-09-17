require "rails_helper"

RSpec.describe "Scoring golden values (07 Phase 3 #1, #7, #9)" do
  golden = JSON.parse(File.read(Rails.root.join("spec/fixtures/scoring_golden.json")))
  configs = {
    "ledger-default@0.1.0" => JSON.parse(File.read(Rails.root.join("config/scoring/ledger-default-0.1.0.json"))),
    "ledger-strict@0.1.0" => JSON.parse(File.read(Rails.root.join("config/scoring/ledger-strict-0.1.0.json")))
  }

  golden["cases"].each do |kase|
    configs.each do |model, config|
      it "#{kase['suite']} #{kase['checkpoint']} #{kase['claim_handle']} under #{model}" do
        result = Scoring::Calculate.call(kase["input"], config: config, model: model, code_hash: "sha256:test")
        expect(golden_fields(result)).to eq(kase["expected"][model])
        expect(result.trace["model"]).to eq(model)
        expect(result.trace["probability"]).to eq(kase["expected"][model]["probability"])
        expect(result.trace_hash).to eq(Crypto::Hashing.json(result.trace))
      end
    end
  end

  it "reproduces byte-identical traces for the same input and model" do
    kase = golden["cases"].first
    a = Scoring::Calculate.call(kase["input"], config: configs["ledger-default@0.1.0"], model: "ledger-default@0.1.0", code_hash: "sha256:test")
    b = Scoring::Calculate.call(JSON.parse(JSON.generate(kase["input"])), config: configs["ledger-default@0.1.0"], model: "ledger-default@0.1.0", code_hash: "sha256:test")
    expect(Scoring::Trace.canonical(a.trace)).to eq(Scoring::Trace.canonical(b.trace))
    expect(a.trace_hash).to eq(b.trace_hash)
  end

  it "never carries a probability for NOT_APPLICABLE or INSUFFICIENT_EVIDENCE, and always a reason for NOT_APPLICABLE (#5, #8)" do
    golden["cases"].each do |kase|
      configs.each do |model, config|
        result = Scoring::Calculate.call(kase["input"], config: config, model: model, code_hash: "sha256:test")
        if %w[NOT_APPLICABLE INSUFFICIENT_EVIDENCE].include?(result.assessment_state)
          expect(result.probability).to be_nil
          expect(result.stability).to be_nil
          expect(result.trace["probability"]).to be_nil
        end
        expect(result.not_applicable_reason).to be_present if result.assessment_state == "NOT_APPLICABLE"
        expect(result.not_applicable_reason).to be_nil unless result.assessment_state == "NOT_APPLICABLE"
      end
    end
  end

  it "shows strongest-only suppression per group and per direction in the trace (#6)" do
    input = {
      "claim" => { "id" => "C", "type" => "TEXTUAL", "truth_evaluable" => true, "not_evaluable_reason" => nil },
      "snapshot_seq" => 1, "task_checks" => [],
      "links" => [
        { "id" => "L1", "evidence_id" => "E1", "direction" => "SUPPORT", "relevance_strength" => "DIRECT", "interpretive_steps" => 0, "audit_confirmed" => true,
          "evidence" => { "observation_type" => "DIRECT_TEXT", "independence_group_id" => "G1", "source_type" => "PRIMARY_TEXT", "assessment" => {} } },
        { "id" => "L2", "evidence_id" => "E2", "direction" => "SUPPORT", "relevance_strength" => "MODERATE", "interpretive_steps" => 0, "audit_confirmed" => true,
          "evidence" => { "observation_type" => "DIRECT_TEXT", "independence_group_id" => "G1", "source_type" => "PRIMARY_TEXT", "assessment" => {} } },
        { "id" => "L3", "evidence_id" => "E3", "direction" => "CONTRADICT", "relevance_strength" => "WEAK", "interpretive_steps" => 0, "audit_confirmed" => true,
          "evidence" => { "observation_type" => "DIRECT_TEXT", "independence_group_id" => "G1", "source_type" => "PRIMARY_TEXT", "assessment" => {} } },
        { "id" => "L4", "evidence_id" => "E4", "direction" => "QUALIFY", "relevance_strength" => "DIRECT", "interpretive_steps" => 0, "audit_confirmed" => true,
          "evidence" => { "observation_type" => "DIRECT_TEXT", "independence_group_id" => "G1", "source_type" => "PRIMARY_TEXT", "assessment" => {} } }
      ]
    }
    result = Scoring::Calculate.call(input, config: configs["ledger-default@0.1.0"], model: "ledger-default@0.1.0", code_hash: "sha256:test")
    links = result.trace["links"].index_by { |l| l["link"] }
    expect(links["L1"]["effective_weight"]).to eq("1.800000")
    expect(links["L2"]).to include("effective_weight" => "0.000000", "reason" => "dependent_strongest_only", "kept" => "L1")
    expect(links["L3"]["effective_weight"]).to eq("0.180000")
    expect(links["L4"]).to include("effective_weight" => "0.000000", "reason" => "non_directional")
    expect(result.support_groups).to eq(1)
    expect(result.contradict_groups).to eq(1)
    expect(result.contested).to be(true)
    expect(result.trace["evidence_sum"]).to eq("1.620000")
  end

  it "never gives a contradicted state to a claim with only supporting evidence, whatever the prior (#9)" do
    causal = golden["cases"].find { |k| k["suite"] == "public-demo" && k["claim_handle"] == "C6" }
    result = Scoring::Calculate.call(causal["input"], config: configs["ledger-default@0.1.0"], model: "ledger-default@0.1.0", code_hash: "sha256:test")
    expect(result.probability).to eq("0.3792")
    expect(result.assessment_state).to eq("UNRESOLVED")
    expect(result.contradict_groups).to eq(0)
  end

  it "flags values within the boundary guard of a rounding boundary (#11)" do
    guard = "1e-6"
    expect(Scoring::Decimal.near_boundary?(BigDecimal("0.12345000000001"), 4, guard)).to be(true)
    expect(Scoring::Decimal.near_boundary?(BigDecimal("0.123449999999"), 4, guard)).to be(true)
    expect(Scoring::Decimal.near_boundary?(BigDecimal("0.12340"), 4, guard)).to be(false)
    expect(Scoring::Decimal.near_boundary?(BigDecimal("0.1234512"), 4, guard)).to be(false)
    kase = golden["cases"].first
    expect(Scoring::Calculate.call(kase["input"], config: configs["ledger-default@0.1.0"], model: "ledger-default@0.1.0", code_hash: "sha256:test").trace["rounding_boundary"]).to be(false)
  end
end
