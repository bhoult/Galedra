require "rails_helper"

# A reader should not have to append ?model= to every link to see the model they
# trust (owner, 2026-09-22). The preference is remembered — on the account when
# signed in, in the session when not.
RSpec.describe "Choosing which model answers", type: :request do
  include GraphHelpers
  before { release_models }

  let(:password) { "correct horse battery staple" }
  let(:strict) { Scoring::Registry.released.find { |m| m.name == "ledger-strict" } }
  let(:default_model) { Scoring::Registry.default_model }

  def claim_with_evidence
    pair, = register_key
    source = create_source(pair, title: "A report")
    claim = create_claim(pair, "A claim with evidence behind it.", type: "CAUSAL")
    link_evidence(pair, create_evidence(pair, create_location(pair, source)), claim)
    claim
  end

  it "offers the choice in the header and remembers it for a signed-out reader" do
    get "/"
    expect(response.body).to include("model-picker")

    post "/preferences/model", params: { model: strict.full_name }, headers: { "HTTP_REFERER" => root_url }
    expect(response).to have_http_status(:redirect)

    claim = claim_with_evidence
    get "/claims/#{claim.id}?calculation=1"
    expect(response.body).to include(strict.full_name)
  end

  it "keeps it on the account when there is one" do
    user = User.create!(email_address: "reader@example.com", password: password)
    post "/session", params: { email_address: user.email_address, password: password }

    post "/preferences/model", params: { model: strict.full_name }
    expect(user.reload.preferred_model).to eq(strict.full_name)

    # And it survives a new session, which a session-scoped one would not.
    delete "/session"
    post "/session", params: { email_address: user.email_address, password: password }
    claim = claim_with_evidence
    get "/claims/#{claim.id}?calculation=1"
    expect(response.body).to include(strict.full_name)
  end

  # The one that matters: a link that names a model must show the same answer to
  # whoever opens it, or two readers of one URL see two numbers and nothing says
  # why.
  it "lets a link that names a model override the preference" do
    post "/preferences/model", params: { model: strict.full_name }
    claim = claim_with_evidence

    get "/claims/#{claim.id}?calculation=1&model=#{default_model.full_name}"
    expect(response.body).to include(default_model.full_name)
  end

  it "ignores a model that is not released, rather than failing" do
    post "/preferences/model", params: { model: "ledger-invented@9.9.9" }
    claim = claim_with_evidence

    get "/claims/#{claim.id}"
    expect(response).to have_http_status(:ok)
  end

  it "gives each released model a page of its own" do
    Scoring::Registry.released.each do |model|
      get "/scoring/models/#{model.full_name}"
      expect(response).to have_http_status(:ok), "#{model.full_name} has no page"
      expect(response.body).to include(model.config_hash)
      expect(response.body).to include(model.semantic_version)
    end

    get "/scoring/models/ledger-invented@9.9.9"
    expect(response).to redirect_to(scoring_path)
  end
end
