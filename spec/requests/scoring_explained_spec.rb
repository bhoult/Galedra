require "rails_helper"

# "0.6 × 0.9 × 0.850000 × 1.0 × 1.0 × 1.0 ... but I have no idea what those
# numbers are" (owner, 2026-09-22). The working was on the page and unreadable:
# bare factors, with their names only in a tooltip, which is invisible on a
# phone. The numbers now carry their names, and each name links to the section
# here that says what it is and why it is there.
RSpec.describe "How a score is worked out", type: :request do
  include GraphHelpers
  before { release_models }

  it "explains every factor, with the numbers read from the released model" do
    get "/scoring"
    expect(response).to have_http_status(:ok)
    body = response.body
    model = Scoring::Registry.default_model

    expect(body).to include(model.full_name)
    # Each factor the working can show has a section to link to.
    %w[relevance observation interpretation authenticity extraction independence prior combining states].each do |anchor|
      expect(body).to include(%(id="#{anchor}")), "no section for #{anchor}"
    end
    # And the numbers are the model's own, not a second copy written in prose.
    expect(body).to include(model.config["relevance_weight"]["DIRECT"])
    expect(body).to include(model.config["interpretive_step_penalty"])
    expect(body).to include(model.config["state_thresholds"]["SUPPORTED"])
    expect(body).to include(model.config["prior"]["CAUSAL"])
  end

  # A line each, and the rest on the model's own page. A list that printed every
  # model's settings was fine at four and unreadable at a hundred.
  it "lists every released model in one line, and links each to its own page" do
    get "/scoring"
    body = response.body
    models = Scoring::Registry.released.to_a
    expect(models.size).to be >= 2

    models.each do |m|
      expect(body).to include(scoring_model_path(name: m.full_name)), "#{m.full_name} is not linked"
    end
    expect(body).to include("Scores every claim type that can be scored")
    expect(body).to include("Declines to score the types where models differ most")
    # And not the full settings of every model, which is what the page had.
    expect(body).not_to include("Where it differs from")
    expect(body).not_to include("config sha256:")
  end

  # Most models will never have a sentence written about them. A true derived
  # line is better than a blank.
  it "describes a model nobody has written prose for" do
    released = Scoring::Registry.released.first
    unknown = ScoringModel.new(name: "ledger-experimental", semantic_version: "1.4.2",
                               config: released.config.merge("scored_types" => %w[OBSERVATIONAL QUANTITATIVE]))
    what, version = Scoring::ModelNotes.summary(unknown)

    expect(what).to include("Scores 2 claim types")
    expect(version).to be_nil
  end

  it "gives a model's own page the detail the list leaves out" do
    model = Scoring::Registry.default_model
    get "/scoring/models/#{model.full_name}"

    expect(response.body).to include(model.config_hash)
    expect(response.body).to include(model.released_seq.to_s)
    expect(response.body).to include("claim types it scores").or include("What it scores")
  end

  # A weight table that differs in one entry is reported as that one entry.
  # Printing both tables whole is how a difference hides inside forty numbers
  # that are the same.
  it "reports a difference inside a table as the entry that differs" do
    default = Scoring::Registry.find("ledger-default@0.1.0")
    strict = Scoring::Registry.find("ledger-strict@0.1.0")
    notes = Scoring::ModelNotes.for(default, [ default, strict ])

    differing = notes[:from_sibling][:differences]
    expect(differing.map(&:first)).to include("observation weight: expert analysis")
    expect(differing.find { |what,| what == "observation weight: expert analysis" }).to eq([ "observation weight: expert analysis", "0.0", "0.3" ])
    # And not the whole table.
    expect(differing.map(&:last).join).not_to include("measurement 1.0")
  end

  # `ledger-default@0.1.0` looks enough like an email address that Cloudflare
  # rewrote it to "[email protected]" in the tunnel, while the app served it
  # correctly. Every model name on this page carries the opt-out.
  it "keeps a model name from being mistaken for an email address" do
    get "/scoring"
    expect(response.body).to include("<!--email_off-->")
    expect(response.body).to include("ledger-default@")
  end

  it "says what a score is not, before saying what it is" do
    get "/scoring"
    expect(response.body).to include("not a measure of truth")
    expect(response.body).to include("Insufficient evidence")
    expect(response.body).to include("Not applicable")
  end

  it "shows a different model's numbers when asked for one" do
    strict = Scoring::Registry.released.find { |m| m.name == "ledger-strict" }
    get "/scoring", params: { model: strict.full_name }

    expect(response.body).to include(strict.full_name)
  end

  # The link from the working to the explanation is the whole point.
  it "is linked from the working on a claim page, factor by factor" do
    pair, = register_key
    source = create_source(pair, title: "A report")
    claim = create_claim(pair, "A claim with evidence behind it.")
    link_evidence(pair, create_evidence(pair, create_location(pair, source)), claim, strength: "MODERATE")

    get "/claims/#{claim.id}?calculation=1"
    body = response.body

    expect(body).to include(scoring_path.to_s)
    expect(body).to include("#relevance")
    # The factor is named on the page, not only in a title attribute.
    expect(body).to match(/relevance.{0,120}MODERATE/m)
  end
end
