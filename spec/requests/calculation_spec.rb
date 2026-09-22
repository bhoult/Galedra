require "rails_helper"

# "Show calculation" showed the result, the state, the model and the trace hash
# — the inputs and the answer, with the working left out (owner, 2026-09-22).
# A number a reader cannot check is a number they have to take on trust, which
# is the one thing this project is for not doing.
RSpec.describe "The working behind a number", type: :request do
  include GraphHelpers
  before { release_models }

  def claim_with_evidence
    pair, = register_key
    source = create_source(pair, title: "A report")
    claim = create_claim(pair, "A claim with one piece of evidence behind it.")
    link_evidence(pair, create_evidence(pair, create_location(pair, source)), claim,
                  direction: "SUPPORT", strength: "STRONG", steps: 1)
    claim
  end

  it "shows each factor, the product, and the sum that becomes the probability" do
    claim = claim_with_evidence

    get "/claims/#{claim.id}?calculation=1"
    expect(response).to have_http_status(:ok)
    body = response.body

    expect(body).to include("How the number was reached")
    # The combination, in the order the algorithm does it (03 §4 Step 4).
    expect(body).to include("prior").and include("log-odds").and include("probability")
    seq = Contribution.maximum(:seq)
    trace = Scoring::Score.call(Claim.find(claim.id), seq, Scoring::Registry.default_model).trace
    expect(body).to include(trace["prior_log_odds"])
    expect(body).to include(trace["evidence_sum"])
    expect(body).to include(trace["posterior_log_odds"])
    expect(body).to include(trace["probability"])
  end

  # The factors are read from the model's config, and they have to multiply out
  # to the magnitude the scorer recorded, or the page is lying about its own
  # arithmetic.
  it "shows factors that multiply to the weight the scorer recorded" do
    claim = claim_with_evidence
    seq = Contribution.maximum(:seq)
    model = Scoring::Registry.default_model
    trace = Scoring::Score.call(Claim.find(claim.id), seq, model).trace

    working = Cards::Calculation.call(trace, model.config)
    row = working[:links].first

    product = row[:factors].map { |f| BigDecimal(f.value) }.reduce(:*)
    expect(Scoring::Decimal.fixed(product, 6)).to eq(row[:magnitude])
    expect(row[:factors].map(&:name)).to include("relevance", "observation", "interpretation")
    # An interpretive step is shown as the subtraction, not just its result.
    expect(row[:factors].find { |f| f.name == "interpretation" }.label).to include("1 −")
  end

  # A model that does not declare a factor must not appear to weigh by it.
  it "shows only the factors the model declares" do
    claim = claim_with_evidence
    seq = Contribution.maximum(:seq)
    old_model = Scoring::Registry.find("ledger-default@0.1.0")
    new_model = Scoring::Registry.find("ledger-default@0.2.0")

    old_row = Cards::Calculation.call(Scoring::Score.call(Claim.find(claim.id), seq, old_model).trace, old_model.config)[:links].first
    new_row = Cards::Calculation.call(Scoring::Score.call(Claim.find(claim.id), seq, new_model).trace, new_model.config)[:links].first

    expect(old_row[:factors].map(&:name)).not_to include("provenance")
    expect(new_row[:factors].map(&:name)).to include("provenance")
  end

  it "says why a link was not counted, rather than showing a bare zero" do
    pair, = register_key
    source = create_source(pair, title: "A report")
    claim = create_claim(pair, "A claim with two readings of one passage behind it.")
    location = create_location(pair, source)
    # Distinct statements, or the two payloads are byte-identical and the second
    # append returns the first by idempotency key — one link, not two.
    [ "One reading of the passage.", "Another reading of the same passage." ].each do |statement|
      link_evidence(pair, create_evidence(pair, location, statement: statement), claim,
                    direction: "SUPPORT", strength: "STRONG")
    end

    get "/claims/#{claim.id}?calculation=1"
    # One of the two is suppressed as dependent, and the page says so and names
    # the one that was kept.
    expect(response.body).to include("dependent strongest only")
  end

  it "does not pretend to a calculation when there is no number" do
    pair, = register_key
    claim = create_claim(pair, "Nobody should do that.", type: "NORMATIVE")

    get "/claims/#{claim.id}?calculation=1"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No probability")
  end
end
