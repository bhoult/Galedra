require "rails_helper"

RSpec.describe "Analyze text (07 Phase 6 #3, 02 §4, 06 §6)", type: :system do
  before { release_models }

  def sign_up(email = "curator@example.com")
    visit new_user_path
    fill_in "Email", with: email
    fill_in "Password", with: "correct horse battery staple"
    fill_in "Confirm password", with: "correct horse battery staple"
    click_button "Create account"
    expect(page).to have_text("server-held signing key")
  end

  it "turns a pasted paragraph into a signed source, warns about non-atomic claims, and records the accepted claims with a per-source card" do
    sign_up
    visit new_analyze_path
    fill_in "Title", with: "AI-drafted memo"
    fill_in "Text", with: "The Watchers descended, taught metallurgy, fathered giants, and caused corruption. Remote work boosts productivity: 62% of remote workers report higher productivity (Journal of Distributed Work Research, 2025). Companies should adopt remote work."
    click_button "Analyze"

    expect(page).to have_text("Proposed claims")
    expect(page).to have_css(".warning", text: /comma-separated series|conjunction/)
    expect(page).to have_field("claims[0][canonical_text]", with: "The Watchers descended, taught metallurgy, fathered giants, and caused corruption.")
    expect(page).to have_field("claims[1][canonical_text]", with: "Remote work boosts productivity.")
    expect(page).to have_select("claims[1][claim_type]", selected: "CAUSAL")
    expect(page).to have_select("claims[4][claim_type]", selected: "NORMATIVE")

    uncheck "claims[0][include]"
    (1..4).each { |i| check "claims[#{i}][affirms_not_private_individual]" }
    click_button "Submit claims"

    expect(page).to have_text("4 claims recorded as signed contributions")
    expect(page).to have_text("4 claims checked")
    expect(page).to have_css(".badge", text: /Not assessed/)
    expect(page).to have_text("never a score for the source or its author")
    expect(page).not_to match(/speaker score|truth score|\d+% true/i)

    click_button "Create verification tasks"
    expect(page).to have_text("tasks created")
    expect(page).to have_text("OPPOSING_EVIDENCE_SEARCH")

    contribution = Contribution.where(action_type: "CREATE_CLAIM").in_order.last
    expect(contribution.custody).to eq("SERVER")
    expect(contribution.current_status).to eq("ACCEPTED")
    visit contributor_path(User.last.custodied_key.contributor)
    expect(page).to have_text("server-held key")
  end

  it "refuses an unaffirmed claim with the spec's error and no log entry" do
    sign_up("other@example.com")
    visit new_analyze_path
    fill_in "Text", with: "Jane Doe owes money."
    click_button "Analyze"
    count = Contribution.count
    click_button "Submit claims"
    expect(page).to have_text("PRIVATE_INDIVIDUAL_AFFIRMATION_REQUIRED")
    expect(Contribution.count).to eq(count)
  end
end
