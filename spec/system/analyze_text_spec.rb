require "rails_helper"

# Stage 46: Analyze text stores the text and opens its breakdown; the claims
# come from an assistant or a person, never from the server.
RSpec.describe "Analyze text (07 Phase 6 #3, 02 §4, 06 §5; Stage 46)", type: :system do
  before { release_models }

  def sign_up(email = "curator@example.com")
    visit new_user_path
    fill_in "Email", with: email
    fill_in "Password", with: "correct horse battery staple"
    fill_in "Confirm password", with: "correct horse battery staple"
    click_button "Create account"
    expect(page).to have_text("server-held signing key")
  end

  it "turns a pasted paragraph into a signed source with an extraction task, and records a person's own breakdown with a per-source card" do
    sign_up
    visit new_analyze_path
    fill_in "Title", with: "AI-drafted memo"
    fill_in "Text", with: "The Watchers descended, taught metallurgy, fathered giants, and caused corruption. Remote work boosts productivity: 62% of remote workers report higher productivity (Journal of Distributed Work Research, 2025). Companies should adopt remote work."
    click_button "Analyze"

    expect(page).to have_text("Break this text into claims")
    expect(page).to have_text("Galedra does not break a text into claims itself")
    expect(page).to have_css("pre.prompt", text: /galedra: Break the text below.*source: "/m)
    expect(page).to have_text("1 claim-extraction task")
    expect(page).to have_field("claims[0][canonical_text]", with: "")
    expect(Claim.count).to eq(0)

    fill_in "claims[0][canonical_text]", with: "The Watchers descended, taught metallurgy, fathered giants, and caused corruption."
    click_button "Check wording"
    expect(page).to have_css(".warning", text: /comma-separated series|conjunction/)
    expect(Claim.count).to eq(0)

    fill_in "claims[0][canonical_text]", with: "Remote work boosts productivity."
    select "CAUSAL", from: "claims[0][claim_type]"
    fill_in "claims[1][canonical_text]", with: "Journal of Distributed Work Research (2025) reports that 62% of remote workers report higher productivity."
    select "TEXTUAL", from: "claims[1][claim_type]"
    fill_in "claims[2][canonical_text]", with: "Companies should adopt remote work."
    select "NORMATIVE", from: "claims[2][claim_type]"
    (0..2).each { |i| check "claims[#{i}][affirms_not_private_individual]" }
    click_button "Record claims"

    expect(page).to have_text("3 claims recorded as signed contributions")
    expect(page).to have_text("3 claims checked")
    expect(page).to have_css(".badge", text: /Not assessed/)
    expect(page).to have_text("never a score for the source or its author")
    expect(page).not_to match(/speaker score|truth score|\d+% true/i)
    # The person broke their own text down, so the volunteer task closed.
    expect(Task.where(task_type: "CLAIM_EXTRACTION").pluck(:status)).to eq([ "CANCELLED" ])

    click_button "Create verification tasks"
    expect(page).to have_text("tasks created")
    expect(page).to have_text("OPPOSING_EVIDENCE_SEARCH")

    contribution = Contribution.where(action_type: "CREATE_CLAIM").in_order.last
    expect(contribution.custody).to eq("SERVER")
    expect(contribution.current_status).to eq("ACCEPTED")
    visit contributor_path(User.last.custodied_key.contributor)
    expect(page).to have_text("server-held key")
  end

  it "refuses a form with an unaffirmed claim and records none of it" do
    sign_up("other@example.com")
    visit new_analyze_path
    fill_in "Text", with: "Jane Doe owes money. The bank closed early."
    click_button "Analyze"
    count = Contribution.count
    fill_in "claims[0][canonical_text]", with: "The bank closed early."
    check "claims[0][affirms_not_private_individual]"
    fill_in "claims[1][canonical_text]", with: "Jane Doe owes money."
    click_button "Record claims"
    expect(page).to have_text("PRIVATE_INDIVIDUAL_AFFIRMATION_REQUIRED")
    expect(page).to have_text("Nothing was recorded")
    expect(Contribution.count).to eq(count)
  end
end
