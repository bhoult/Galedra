require "rails_helper"

# Stage 35, cross-checked against reference_scorer.py's provenance suite: the
# same two inputs, the same four answers, computed by two implementations that
# share no code. A golden that only one side can produce proves nothing.
RSpec.describe "Provenance is not corroboration (Stage 35)" do
  def config(version, strict: false)
    Scoring::Registry.load_config(Rails.root.join("config/scoring/ledger-#{strict ? 'strict' : 'default'}-#{version}.json"))
  end

  def link(id, evidence_id, origin:, passage:, self_referential: false)
    { "id" => id, "evidence_id" => evidence_id, "direction" => "SUPPORT", "self_referential" => self_referential,
      "relevance_strength" => "DIRECT", "interpretive_steps" => 0, "created_seq" => 1, "audit_confirmed" => false,
      "evidence" => { "observation_type" => "DIRECT_TEXT", "independence_group_id" => nil, "origin" => origin,
                      "passage" => passage, "source_type" => "WEBSITE", "assessment" => {}, "created_seq" => 1 } }
  end

  def input(links)
    { "claim" => { "id" => "C1", "type" => "OBSERVATIONAL", "truth_evaluable" => true, "not_evaluable_reason" => nil },
      "snapshot_seq" => 1, "links" => links, "task_checks" => [] }
  end

  def score(links, version)
    r = Scoring::Calculate.call(input(links), config: config(version), model: "ledger-default@#{version}", code_hash: "sha256:x")
    [ r.assessment_state, r.probability&.to_s, r.stability, r.support_groups ]
  end

  # The prior for OBSERVATIONAL is 0.50, so the log-odds start at zero and one
  # DIRECT x DIRECT_TEXT link is 2.0 * 0.9 = 1.8, giving sigmoid(1.8) = 0.8581.
  it "gives a claim's own origin no weight, while 0.1.0 is unmoved" do
    own = [ link("L1", "E1", origin: "uri:example.org/a", passage: "p1", self_referential: true) ]

    expect(score(own, "0.1.0")).to eq([ "SUPPORTED", "0.8581", "MEDIUM", 1 ])
    expect(score(own, "0.2.0")).to eq([ "INSUFFICIENT_EVIDENCE", nil, nil, 0 ]),
      "a claim supported only by the source it came from is unchecked, not contradicted"
  end

  it "counts one passage entered twice as one, while 0.1.0 counts it twice" do
    twice = [ link("L1", "E1", origin: "uri:example.org/b", passage: "p2"),
              link("L2", "E2", origin: "uri:example.org/b", passage: "p2") ]

    expect(score(twice, "0.1.0")).to eq([ "SUPPORTED", "0.9734", "HIGH", 2 ])
    # One reading, so one group: the number falls and so does the confidence in
    # it, because two groups meet the minimum for HIGH and one does not.
    expect(score(twice, "0.2.0")).to eq([ "SUPPORTED", "0.8581", "MEDIUM", 1 ])
  end

  it "leaves two genuine passages of one document independent" do
    distinct = [ link("L1", "E1", origin: "uri:example.org/c", passage: "p1"),
                 link("L2", "E2", origin: "uri:example.org/c", passage: "p2") ]

    expect(score(distinct, "0.2.0")).to eq([ "SUPPORTED", "0.9734", "HIGH", 2 ]),
      "a qualifier and a supporting line from one report are not each other repeated"
  end
end
