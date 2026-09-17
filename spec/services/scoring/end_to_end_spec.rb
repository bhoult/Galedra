require "rails_helper"

RSpec.describe "Scoring end to end through the write path (07 Phase 3 #1, #2; scenarios C, D, J)" do
  before { release_models }

  shared_examples "reproduces the golden table" do |suite, builder|
    it "reproduces every #{suite} golden row for both models (except #{DemoGraphs::DEFERRED_GOLDEN_FIELDS.join(', ')} until audits and tasks exist)" do
      graph = send(builder)
      fields = golden_cases_for(suite).first["expected"].values.first.keys - DemoGraphs::DEFERRED_GOLDEN_FIELDS
      failures = []
      golden_cases_for(suite).each do |kase|
        seq = graph.checkpoints.fetch(kase["checkpoint"])
        claim = graph.claims.fetch(kase["claim_handle"])
        Scoring::Registry.released.each do |model|
          got = golden_fields(Scoring::Score.call(claim, seq, model)).slice(*fields)
          expected = kase["expected"].fetch(model.full_name).slice(*fields)
          failures << "#{kase['checkpoint']} #{kase['claim_handle']} #{model.full_name}: got #{got} expected #{expected}" unless got == expected
        end
      end
      expect(failures).to eq([])
    end
  end

  include_examples "reproduces the golden table", "public-demo", :build_public_demo
  include_examples "reproduces the golden table", "watchers", :build_watchers_demo

  it "gives byte-identical traces after a cache wipe and after replay, and stable snapshot digests (#1, J)" do
    graph = build_public_demo
    model = Scoring::Registry.default_model
    seq = graph.checkpoints["S5"]
    claim = graph.claims["C2"]

    first = Scoring::Score.call(claim, seq, model)
    expect(ClaimScore.where(claim_id: claim.id, snapshot_seq: seq).count).to eq(1)
    canonical = Scoring::Trace.canonical(first.trace)
    expect(Scoring::Trace.canonical(Scoring::Score.call(claim, seq, model).trace)).to eq(canonical)

    ClaimScore.delete_all
    expect(Scoring::Trace.canonical(Scoring::Score.call(claim, seq, model).trace)).to eq(canonical)

    digests = graph.checkpoints.transform_values { |s| Snapshots::Create.call(seq: s, label: "cp"); Snapshots::Digest.call(s) }
    expect(digests.values.uniq.size).to eq(digests.size)

    Ledger::Replay.call
    expect(ClaimScore.count).to eq(0)
    expect(Scoring::Trace.canonical(Scoring::Score.call(Claim.find(claim.id), seq, model).trace)).to eq(canonical)
    expect(graph.checkpoints.transform_values { |s| Snapshots::Digest.call(s) }).to eq(digests)
    expect(GraphSnapshot.count).to eq(5)
  end

  it "shows the demo's teaching moments: repetition collapses and a qualifier drags the broad claim to unresolved (C, D)" do
    graph = build_public_demo
    model = Scoring::Registry.default_model
    c2 = graph.claims["C2"]
    expect(Scoring::Score.call(c2, graph.checkpoints["S1"], model)).to have_attributes(assessment_state: "SUPPORTED", probability: "0.9085", support_groups: 4, independence_unreviewed: 3)
    expect(Scoring::Score.call(c2, graph.checkpoints["S4"], model)).to have_attributes(assessment_state: "LEANS_SUPPORTED", probability: "0.7146", support_groups: 1)
    expect(Scoring::Score.call(c2, graph.checkpoints["S5"], model)).to have_attributes(assessment_state: "UNRESOLVED", probability: "0.5247")
    expect(Scoring::Score.call(graph.claims["C3"], graph.checkpoints["S5"], model)).to have_attributes(assessment_state: "SUPPORTED", probability: "0.8581")
    expect(ClaimMerge.count).to eq(0)
  end
end
