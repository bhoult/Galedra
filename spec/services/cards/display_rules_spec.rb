require "rails_helper"

RSpec.describe Cards::DisplayRules do
  let(:checklist) { { "a" => { "ok" => true }, "b" => { "ok" => false }, "c" => { "ok" => true }, "d" => { "ok" => false } } }

  it "reports review coverage as a count of checks, never a percentage (rule 5)" do
    expect(described_class.checks_count(checklist)).to eq("2 of 4")
    expect(described_class.checks_done(checklist)).to eq(2)
    expect(described_class.checks_count({})).to eq("0 of 0")
    expect(described_class.checks_count(checklist)).not_to match(/%|high|medium|low/i)
  end

  it "writes a probability only with its model and snapshot, and not at all without one (rules 2, 3)" do
    expect(described_class.stated("0.8581", "ledger-default@0.1.0", 12)).to eq("0.8581 under ledger-default@0.1.0 at snapshot 12")
    expect(described_class.stated(nil, "ledger-default@0.1.0", 12)).to be_nil
  end

  it "labels provisional, contested, and model-dependent assessments (rules 4, 6)" do
    labels = described_class.labels(state: "UNRESOLVED", provisional: true, contested: true, model_dependent: true, review_checklist: checklist)
    expect(labels).to eq([ "Not yet independently audited.", "Evidence points both ways.", "This assessment depends heavily on modeling choices." ])
    expect(described_class.labels(state: "UNRESOLVED", provisional: false, contested: false, model_dependent: false, review_checklist: checklist)).to eq([])
  end

  it "widens the provisional wording when an anonymous contributor's work is counted (Stage 12)" do
    labels = described_class.labels(state: "UNRESOLVED", provisional: true, contested: false, model_dependent: false, review_checklist: checklist, anonymous: true)
    expect(labels.first).to eq("Not yet independently audited; some evidence was recorded by an anonymous contributor.")
  end

  it "adds rule 5's caveat only to a directional state resting on at most one check" do
    thin = { "a" => { "ok" => true }, "b" => { "ok" => false }, "c" => { "ok" => false }, "d" => { "ok" => false } }
    caveat = "Evidence reviewed so far supports this claim, but only 1 of 4 review checks has been done."
    expect(described_class.labels(state: "SUPPORTED", provisional: false, contested: false, model_dependent: false, review_checklist: thin)).to eq([ caveat ])
    expect(described_class.labels(state: "CONTRADICTED", provisional: false, contested: false, model_dependent: false, review_checklist: thin).first).to include("contradicts this claim")
    expect(described_class.labels(state: "UNRESOLVED", provisional: false, contested: false, model_dependent: false, review_checklist: thin)).to eq([])
    expect(described_class.labels(state: "SUPPORTED", provisional: false, contested: false, model_dependent: false, review_checklist: checklist)).to eq([])
  end

  it "is what the answer card shows, so the claim page never states a rule two ways" do
    expect(described_class).to respond_to(:for_result)
    expect(File.read(Rails.root.join("app/views/claims/show.html.erb"))).not_to include("assessment_labels")
  end
end
