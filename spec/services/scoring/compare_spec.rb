require "rails_helper"

RSpec.describe Scoring::Compare do
  it "names scored_types when the models disagree on a causal claim (07 scenario H)" do
    kase = golden["cases"].find { |k| k["suite"] == "public-demo" && k["claim_handle"] == "C6" }
    a = Scoring::Calculate.call(kase["input"], config: default_config, model: "ledger-default@0.1.0", code_hash: "sha256:x")
    b = Scoring::Calculate.call(kase["input"], config: strict_config, model: "ledger-strict@0.1.0", code_hash: "sha256:x")
    diff = described_class.call(a, b, config_a: default_config, config_b: strict_config)

    expect(diff["state_change"]).to eq("from" => "UNRESOLVED", "to" => "NOT_APPLICABLE")
    expect(diff["responsible_config_keys"]).to include("scored_types")
    expect(diff["config_diff"]).to include("name", "scored_types", "model_dependent_types", "observation_weight.EXPERT_ANALYSIS", "prior.CAUSAL")
    expect(diff["assessment"]["ledger-strict@0.1.0"]["not_applicable_reason"]).to eq("NOT_SCORED_BY_MODEL")
  end

  it "names the observation weight for the Watchers interpretive claim" do
    kase = golden["cases"].find { |k| k["suite"] == "watchers" && k["claim_handle"] == "C3" }
    a = Scoring::Calculate.call(kase["input"], config: default_config, model: "ledger-default@0.1.0", code_hash: "sha256:x")
    b = Scoring::Calculate.call(kase["input"], config: strict_config, model: "ledger-strict@0.1.0", code_hash: "sha256:x")
    diff = described_class.call(a, b, config_a: default_config, config_b: strict_config)
    expect(diff["links"].first["responsible"]).to include("observation_weight.EXPERT_ANALYSIS", "scored_types")
    expect(diff["responsible_config_keys"]).to include("scored_types", "observation_weight.EXPERT_ANALYSIS")
  end

  it "reports no differences when the models agree" do
    kase = golden["cases"].find { |k| k["suite"] == "public-demo" && k["claim_handle"] == "C1" }
    a = Scoring::Calculate.call(kase["input"], config: default_config, model: "ledger-default@0.1.0", code_hash: "sha256:x")
    b = Scoring::Calculate.call(kase["input"], config: strict_config, model: "ledger-strict@0.1.0", code_hash: "sha256:x")
    diff = described_class.call(a, b, config_a: default_config, config_b: strict_config)
    expect(diff["state_change"]).to be_nil
    expect(diff["links"]).to eq([])
    expect(diff["responsible_config_keys"]).to eq([])
  end
end
