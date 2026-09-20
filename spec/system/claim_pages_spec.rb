require "rails_helper"

RSpec.describe "Claim pages (07 Phase 6 #3)", type: :system do
  before { release_models }

  let(:curator) { register_key(display_name: "Curator").first }

  it "leads with the answer card and keeps the number behind Show calculation; review checks are a count" do
    graph = build_public_demo
    c2 = graph.claims["C2"]
    visit claim_path(c2, snapshot_seq: graph.checkpoints["S5"])

    expect(page).to have_css(".card .headline", text: "Unresolved")
    expect(page).to have_text("review checks 3 of 4")
    expect(page).not_to have_text("0.5247")
    expect(page.text).not_to match(/\d+% of evidence|coverage:\s*(high|medium|low)/i)

    expect(page).not_to have_text("0.5247")
    click_link "Show calculation"
    within("#calculation") do
      expect(page).to have_text("0.5247 under #{Scoring::Registry.default_model.full_name} at snapshot #{graph.checkpoints['S5']}")
      expect(page).to have_text("Review checks: 3 of 4")
    end
    expect(page).to have_css("pre#trace", text: '"probability": "0.5247"')
    click_link "Hide calculation"
    expect(page).not_to have_text("0.5247")
    expect(page).to have_text("Main unresolved issue")
    expect(page).to have_text("A narrower version of this claim is supported.")
  end

  it "shows no number at all for a claim with insufficient evidence, and the reason for a value judgment" do
    claim = create_claim(curator, "Nothing bears on this yet.")
    visit claim_path(claim)
    expect(page).to have_css(".headline", text: "Insufficient evidence")
    expect(page.body).not_to match(/\b0\.\d{4}\b/)
    click_link "Show calculation"
    expect(page).to have_text("No probability")
    expect(page.body).not_to match(/\b0\.\d{4} under/)

    normative = create_claim(curator, "Companies should adopt remote work.", type: "NORMATIVE")
    visit claim_path(normative)
    expect(page).to have_css(".headline", text: "Not assessed")
    expect(page).to have_text("value judgment")
  end

  it "labels unaudited links provisional and switches traces with the model selector" do
    source = create_source(curator, type: "DATASET", content: "Survey: 62% of 400 respondents reported higher productivity.")
    evidence = create_evidence(curator, create_location(curator, source), observation: "DATASET_RESULT")
    causal = create_claim(curator, "Remote work causes higher productivity.", type: "CAUSAL")
    link_evidence(curator, evidence, causal, strength: "WEAK", steps: 2)

    visit claim_path(causal)
    expect(page).to have_text("Not yet independently audited.")
    expect(page).to have_text("depends heavily on modeling choices")
    expect(page).to have_css(".headline", text: "Unresolved")
    click_link "Show calculation"
    expect(page).to have_text("the default model, not the answer")
    expect(page).to have_css("pre#trace", text: %("model": "#{Scoring::Registry.default_model.full_name}"))

    select "ledger-strict@0.1.0", from: "model"
    click_button "View"
    expect(page).to have_css(".headline", text: "Not assessed")
    expect(page).to have_text("This model does not score claims of this type.")
    click_link "Show calculation"
    expect(page).to have_text("an alternative model")
    expect(page).to have_css("pre#trace", text: '"model": "ledger-strict@0.1.0"')
  end

  it "renders a public stub at a quarantined claim's URL" do
    moderator, = register_moderator
    claim = create_claim(curator, "About Jane Doe of 12 Example Street.")
    quarantine(moderator, claim, reason: "PRIVATE_INDIVIDUAL")
    visit claim_path(claim)
    expect(page.status_code).to eq(200)
    expect(page).to have_css(".headline", text: "Quarantined")
    expect(page).to have_text("PRIVATE_INDIVIDUAL")
    expect(page).to have_text(moderator.key_id)
    expect(page).not_to have_text("Jane Doe")
    expect(page).to have_link("moderation log")
  end

  it "browses claims with filters and reads the log, contributions, contributors, tasks, weaknesses, moderation, and snapshots" do
    graph = build_public_demo
    visit claims_path(q: "productivity")
    expect(page).to have_link(graph.claims["C2"].canonical_text)
    visit claims_path(state: "NOT_APPLICABLE")
    expect(page).to have_link("Companies should adopt remote work.")
    expect(page).not_to have_link(graph.claims["C2"].canonical_text)

    visit contributions_path
    expect(page).to have_text("REGISTER_KEY")
    click_link "0", match: :first
    expect(page).to have_text("client signature: verifies")
    expect(page).to have_text("chain: intact")

    visit contributor_path(ReputationEvent.where(task_type: "MANUAL").first.contributor)
    expect(page).to have_text("Audited reliability")
    expect(page).to have_text("MANUAL")
    expect(page).not_to match(/followers|likes|prestige/i)

    visit tasks_path
    expect(page).to have_text("Recently completed")
    visit task_path(graph.handles["T4"])
    expect(page).to have_text("Hand this to my agent")
    expect(page).to have_text("QUALIFIER_CHECK")

    visit weaknesses_path(snapshot_seq: graph.checkpoints["S1"])
    expect(page).to have_text("models disagree (1)")
    expect(page).to have_link("Remote work causes higher productivity.")

    visit moderation_path
    expect(page).to have_text("Public moderation log")

    visit snapshot_path(graph.checkpoints["S1"], compare_seq: graph.checkpoints["S5"])
    expect(page).to have_text("claim score digest")
    expect(page).to have_text("Supported")
    expect(page).to have_text("Unresolved")
  end
end
