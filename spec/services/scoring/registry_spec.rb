require "rails_helper"

RSpec.describe Scoring::Registry do
  it "ships byte-identical copies of the spec's configs" do
    spec_dir = Rails.root.join("docs/epistemic-ledger-poc-spec-v4/epistemic-ledger-poc")
    expect(File.binread(Rails.root.join("config/scoring/ledger-default-0.1.0.json"))).to eq(File.binread(spec_dir.join("scoring-config-v0.1.json")))
    expect(File.binread(Rails.root.join("config/scoring/ledger-strict-0.1.0.json"))).to eq(File.binread(spec_dir.join("scoring-config-strict-v0.1.json")))
  end

  it "accepts both P0 configs" do
    expect(described_class.validate!(default_config)).to be_a(Hash)
    expect(described_class.validate!(strict_config)).to be_a(Hash)
  end

  it "rejects a config with a missing enum key at release (07 Phase 3 #3)" do
    config = default_config
    config["observation_weight"].delete("HEARSAY")
    expect { described_class.validate!(config) }.to raise_error(described_class::Invalid, /observation_weight is missing HEARSAY/)

    config = default_config
    config["prior"].delete("CAUSAL")
    expect { described_class.validate!(config) }.to raise_error(described_class::Invalid, /prior is missing CAUSAL/)

    config = default_config
    config["relevance_weight"]["WEAK"] = 0.2
    expect { described_class.validate!(config) }.not_to raise_error
    config["relevance_weight"]["WEAK"] = "weak"
    expect { described_class.validate!(config) }.to raise_error(described_class::Invalid, /non-decimal/)
  end

  it "rejects a checklist declaring a check no P0 task type can satisfy (07 Phase 3 #10)" do
    config = default_config
    config["review_checklist"] << "replication_reviewed"
    expect { described_class.validate!(config) }.to raise_error(described_class::Invalid, /unknown checks: replication_reviewed/)

    stub_const("Scoring::Checklist::KNOWN", Scoring::Checklist::KNOWN + [ "replication_reviewed" ])
    stub_const("Scoring::Checklist::TASK_CHECKS", Scoring::Checklist::TASK_CHECKS.merge("replication_reviewed" => "REPLICATION_REVIEW"))
    expect { described_class.validate!(config) }.to raise_error(described_class::Invalid, /no P0 task type can satisfy: replication_reviewed/)
  end

  it "releases both models through the log, signed by the system key, and rejects unauthorized or stale releases" do
    models = release_models
    expect(models.map(&:full_name)).to include("ledger-default@0.1.0", "ledger-strict@0.1.0")
    expect(models.map(&:code_hash).uniq).to eq([ described_class.code_hash ])
    expect(models.first.config_hash).to eq(Crypto::Hashing.json(models.first.config))
    expect(described_class.find("ledger-default").full_name).to eq(ScoringModel.where(name: "ledger-default").order(:released_seq).last.full_name)
    expect(described_class.default_model.name).to eq("ledger-default")

    human, = register_key
    expect_rejected("NOT_AUTHORIZED") { append(action_type: "RELEASE_SCORING_MODEL", key_pair: human, payload: described_class.release_payload(default_config)) }

    payload = described_class.release_payload(default_config)
    expect_rejected("ALREADY_RELEASED") { append(action_type: "RELEASE_SCORING_MODEL", key_pair: Crypto::SystemKey.key_pair, custody: "SYSTEM", payload: payload.merge("test_suite_result_hash" => "x")) }

    bumped = default_config.merge("semantic_version" => "0.2.0")
    payload = described_class.release_payload(bumped).merge("code_hash" => "sha256:#{'0' * 64}")
    expect_rejected("CODE_HASH_MISMATCH") { append(action_type: "RELEASE_SCORING_MODEL", key_pair: Crypto::SystemKey.key_pair, custody: "SYSTEM", payload: payload) }

    broken = default_config.merge("semantic_version" => "0.2.0")
    broken["prior"].delete("TEXTUAL")
    expect_rejected("CONFIG_INVALID") { append(action_type: "RELEASE_SCORING_MODEL", key_pair: Crypto::SystemKey.key_pair, custody: "SYSTEM", payload: described_class.release_payload(default_config).merge("config" => broken, "semantic_version" => "0.2.0", "config_hash" => Crypto::Hashing.json(broken))) }
  end

  it "fails the code_hash check when scorer code changes without a new version (07 Phase 3 #4)" do
    release_models
    expect(described_class.verify_code_hash!).to be(true)
    allow(described_class).to receive(:code_hash).and_return("sha256:#{'a' * 64}")
    expect { described_class.verify_code_hash! }.to raise_error(described_class::CodeHashMismatch, /release a new version/)
  end

  it "scores through a released model and releasing strict changes no default trace (07 Phase 3 #7)" do
    kase = golden["cases"].first
    default_only = Scoring::Calculate.call(kase["input"], config: default_config, model: "ledger-default@0.1.0", code_hash: "sha256:x")
    models = release_models
    scored = described_class.score(kase["input"], "ledger-default@0.1.0")
    expect(golden_fields(scored)).to eq(golden_fields(default_only))
    expect(scored.trace["code_hash"]).to eq(models.first.code_hash)
    expect(scored.trace.except("code_hash")).to eq(default_only.trace.except("code_hash"))
    expect(described_class.score(kase["input"], "ledger-strict@0.1.0").trace["model"]).to eq("ledger-strict@0.1.0")
  end
end
