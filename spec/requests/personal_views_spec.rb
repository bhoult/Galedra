require "rails_helper"

RSpec.describe "Affiliations and personal views (spec 02 §3.6a, Article XV)", type: :request do
  include GraphHelpers
  before { release_models }

  let(:password) { "correct horse battery staple" }
  let!(:claim) { create_claim(register_key.first, "Remote work raises productivity.", type: "CAUSAL") }

  def user(email)
    User.create!(email_address: email, password: password)
  end

  def sign_in(u)
    post "/session", params: { email_address: u.email_address, password: password }
  end

  def sign_out
    delete "/session"
  end

  it "lets a person declare affiliations privately, register and change a view, and keeps it out of the assessment" do
    me = user("me@example.com")
    sign_in(me)
    get "/account"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Democrat").and include("Atheist").and include("Millennial")

    patch "/account", params: { affiliations: [ "democrat", "atheist", "millennial", "not-a-thing" ] }
    expect(me.user_affiliations.pluck(:affiliation)).to match_array(%w[democrat atheist millennial])
    patch "/account", params: { affiliations: [ "democrat" ] }
    expect(me.user_affiliations.pluck(:affiliation)).to eq([ "democrat" ])

    before = Scoring::Score.call(claim, Contribution.maximum(:seq), Scoring::Registry.default_model).trace_hash
    post "/claims/#{claim.id}/view", params: { stance: "AGREE", rationale: "matches my experience" }
    expect(response).to redirect_to("/claims/#{claim.id}#your-view")
    expect(me.personal_assessments.find_by(claim: claim)).to have_attributes(stance: "AGREE", rationale: "matches my experience", visibility: "PRIVATE")
    post "/claims/#{claim.id}/view", params: { stance: "DISAGREE" }
    expect(me.personal_assessments.count).to eq(1)
    expect(me.personal_assessments.first.stance).to eq("DISAGREE")
    post "/claims/#{claim.id}/view", params: { stance: "MAYBE" }
    expect(flash[:alert]).to include("Agree or disagree")
    expect(Scoring::Score.call(claim, Contribution.maximum(:seq), Scoring::Registry.default_model).trace_hash).to eq(before)

    get "/claims/#{claim.id}"
    expect(response.body).to include("You disagree")
    expect(response.body).to include("1 disagree")
    expect(response.body).to include("personal belief, not evidence")
    get "/account"
    expect(response.body).to include("Remote work raises productivity.")

    delete "/claims/#{claim.id}/view"
    expect(me.personal_assessments.count).to eq(0)
    sign_out
    get "/claims/#{claim.id}"
    expect(response.body).to include("Sign in").and include("Nobody has registered a view yet")
  end

  it "breaks views down by affiliation only for groups of five or more, and serves the aggregate over the API" do
    7.times do |i|
      u = user("dem#{i}@example.com")
      u.user_affiliations.create!(affiliation: "democrat")
      u.user_affiliations.create!(affiliation: "boomer") if i < 3
      PersonalAssessment.set!(user: u, claim: claim, stance: i < 5 ? "AGREE" : "DISAGREE")
    end
    5.times do |i|
      u = user("rep#{i}@example.com")
      u.user_affiliations.create!(affiliation: "republican")
      PersonalAssessment.set!(user: u, claim: claim, stance: i < 2 ? "AGREE" : "DISAGREE")
    end

    views = PersonalAssessments::Breakdown.call(claim.id)
    expect(views).to include(agree: 7, disagree: 5, total: 12)
    expect(views[:by_affiliation].map { |r| r[:affiliation] }).to match_array(%w[democrat republican])
    expect(views[:by_affiliation].find { |r| r[:affiliation] == "democrat" }).to include(agree: 5, disagree: 2, group: "Politics")
    expect(views[:by_affiliation].find { |r| r[:affiliation] == "republican" }).to include(agree: 2, disagree: 3)

    get "/api/v1/claims/#{claim.id}/views"
    body = response.parsed_body["views"]
    expect(body["total"]).to eq(12)
    expect(body["by_affiliation"].map { |r| r["label"] }).to match_array([ "Democrat", "Republican" ])
    expect(body["note"]).to include("not evidence")
    get "/api/v1/claims/#{claim.id}"
    expect(response.parsed_body["claim"]).not_to have_key("views")

    get "/claims/#{claim.id}"
    expect(response.body).to include("7 agree · 5 disagree").and include("Democrat").and include("Republican")
    expect(response.body).not_to include("Baby boomer")
  end
end
