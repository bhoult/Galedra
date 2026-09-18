require "rails_helper"

RSpec.describe DisplayHelper, type: :helper do
  it "shows a number only with model and snapshot, and never for unknown states (rules 2, 3)" do
    expect(helper.assessment_number(assessment_state: "SUPPORTED", probability: "0.8581", model: "ledger-default@0.1.0", snapshot_seq: 12))
      .to eq("0.8581 under ledger-default@0.1.0 at snapshot 12")
    expect(helper.assessment_number(assessment_state: "INSUFFICIENT_EVIDENCE", probability: nil, model: "m", snapshot_seq: 1)).to be_nil
    expect(helper.assessment_number(assessment_state: "NOT_APPLICABLE", probability: "0.5000", model: "m", snapshot_seq: 1)).to be_nil
  end

  it "renders review coverage as a count of checks, never a percentage (rule 5)" do
    checklist = { "a" => { "ok" => true }, "b" => { "ok" => false }, "c" => { "ok" => true }, "d" => { "ok" => false } }
    expect(helper.review_checks_text(checklist)).to eq("Review checks: 2 of 4")
    expect(helper.review_checks_text(checklist)).not_to match(/%|high|medium|low/i)
  end

  it "labels provisional, contested, and model-dependent assessments (rules 4, 6)" do
    expect(helper.assessment_labels(provisional: true, contested: true, model_dependent: true))
      .to eq([ "Not yet independently audited.", "Evidence points both ways.", "This assessment depends heavily on modeling choices." ])
    expect(helper.assessment_labels(provisional: false, contested: false, model_dependent: false)).to eq([])
  end

  it "uses neutral state wording and plain-words reasons (rules 10, 12)" do
    expect(helper.state_label("LEANS_CONTRADICTED")).to eq("Leans contradicted")
    expect(helper.state_label("SUPPORTED")).not_to match(/true|confirmed|debunked/i)
    expect(helper.not_applicable_text("NORMATIVE_OR_VALUE")).to include("value judgment")
    expect(helper.evidence_counts_text(3, 2)).to eq("3 sources, 2 independent lineages")
  end
end
