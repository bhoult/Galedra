require "rails_helper"

# Stage 39. The pages people actually open asked the database one row at a time.
# Measured on the dev node at 288 claims before the fix: the outline page issued
# **5,343 statements** and took 2.8–3.3 s, `/sections` 1,870, `/weaknesses`
# 1,872. Two of those numbers are per row on the page; one of them,
# `Contributions::Standing`, was linear in the length of the whole log as well,
# so at the seeded corpus the outline page did not return at all.
#
# Each budget below is a count taken against this fixture, written down so the
# next change has to argue with it rather than with a commit message. Run against
# the code as it stood, four of the five examples fail; against this one the
# same fixture costs:
#
#   outline page      100 -> 26 statements
#   outline index      44 -> 19
#   weaknesses        141 -> 88, and 586 -> 98 once the corpus doubled
#
# The budgets sit just above those numbers, not at double them. A budget of 60
# against a measured 26 lets the page regress to twice its cost and still pass,
# which is a budget that buys nothing (code review, 2026-09-22). Raise one
# deliberately, with the reason, when a change earns it.
#
# The last pair is the one that matters: the old page paid for every claim in
# the corpus, the new one pays for the rows it shows.
RSpec.describe "What a read path costs", type: :request do
  include GraphHelpers
  before { release_models }

  def statements
    n = 0
    counter = ->(*, payload) { n += 1 unless payload[:name].to_s == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    n
  end

  # An outline with text, claims placed in it, evidence on them, and open work:
  # the shape a person is handed a link to.
  def outline
    pair, = register_key
    source = create_source(pair, title: "A transcript", content: "#{'A sentence of the transcript. ' * 40}")
    locations = 6.times.map { |i| create_location(pair, source, start: i * 30, finish: (i * 30) + 29) }
    # A section's own text is a TRANSCRIPTION: only a quotation is checked
    # against the source, so a reading may not be a CHAR_RANGE quote.
    readings = 6.times.map do |i|
      text = "Part #{i + 1} of the transcript, as read."
      row_for(append(action_type: "CREATE_SOURCE_LOCATION", key_pair: pair,
                     payload: { "source_id" => source.id, "locator_type" => "TRANSCRIPTION", "locator" => {},
                                "excerpt" => text, "excerpt_hash" => Crypto::Hashing.bytes(text) }), "location", SourceLocation)
    end
    result = append(action_type: "CREATE_SECTION", key_pair: pair,
                    payload: { "source_id" => source.id, "sections" => [
                      { "heading" => "The transcript", "sections" => readings.each_with_index.map do |reading, i|
                        { "heading" => "Part #{i + 1}", "reading_location_id" => reading.id }
                      end } ] })
    root = Section.find(Ledger::Ids.derive(result.contribution.id, "section", 0))
    leaves = root.children.order(:position).to_a

    leaves.each_with_index do |leaf, i|
      claim = create_claim(pair, "A checkable claim from part #{i + 1} of the transcript.")
      append(action_type: "PLACE_CLAIM", key_pair: pair, payload: { "claim_id" => claim.id, "section_id" => leaf.id })
      link_evidence(pair, create_evidence(pair, locations[i]), claim)
      Tasks::OpenVerification.call([ claim ], location_for: ->(_c) { locations[i] })
    end
    [ root, leaves ]
  end

  it "renders the outline page in a bounded number of statements" do
    root, = outline

    get "/sections/#{root.id}"
    expect(response).to have_http_status(:ok)
    before = response.body

    n = statements { get "/sections/#{root.id}" }
    expect(response.body).to eq(before), "the page must render identically; this stage changes when rows are fetched, never what is shown"
    expect(n).to be <= 32, "#{n} statements for one outline page"
  end

  it "renders the outline index in a bounded number of statements" do
    outline

    get "/sections"
    n = statements { get "/sections" }
    expect(response).to have_http_status(:ok)
    expect(n).to be <= 24, "#{n} statements for the outline index"
  end

  # This one is not bounded by a constant, and should not be: the page builds
  # "what would most change this" for the rows it returns, and each of those
  # rebuilds one claim's scorer input on purpose. What it must not do is grow
  # with the **corpus**, so the page size is held still while the claims double.
  # (The per-row cost is `Scoring::BuildInput`, still one row at a time; batching
  # that is the half of Stage 38 that was deferred.)
  it "renders the weaknesses page without paying for claims it does not show" do
    outline
    get "/weaknesses?limit=5"
    first = statements { get "/weaknesses?limit=5" }
    expect(response).to have_http_status(:ok)

    outline # twice the claims, the same five rows a kind
    get "/weaknesses?limit=5"
    second = statements { get "/weaknesses?limit=5" }

    expect(second).to be <= first + 10, "#{first} statements became #{second} when the corpus doubled"
    expect(second).to be <= 110, "#{second} statements for five rows a kind"
  end

  # The one that was linear in the log rather than in the page: every append
  # made it dearer, for every row, on every page that asked.
  it "answers whether a set of entries stands accepted in one statement" do
    pair, = register_key
    claims = 8.times.map { |i| create_claim(pair, "A claim, number #{i}, to ask the standing of.") }
    entries = claims.map(&:contribution)
    seq = Contribution.maximum(:seq)

    n = statements { @standing = Contributions::Standing.accepted_set(entries, seq) }
    expect(@standing.size).to eq(entries.size)
    expect(n).to eq(1), "#{n} statements for #{entries.size} entries"

    # And the single-entry question still answers the same way.
    expect(Contributions::Standing.accepted_at?(entries.first, seq)).to be(true)
    expect(Contributions::Standing.accepted_at?(entries.first, entries.first.seq - 1)).to be(false)
  end

  # Stage 39, finding 5: the input is the same for every model, so a rescore
  # under four models should build it once, not four times.
  it "builds a claim's scorer input once per rescore, whatever the model count" do
    pair, = register_key
    claims = 4.times.map { |i| create_claim(pair, "A claim, number #{i}, to rescore.") }
    seq = Contribution.maximum(:seq)
    models = Scoring::Registry.released.to_a
    expect(models.size).to be >= 2

    built = 0
    allow(Scoring::BuildInput).to receive(:call).and_wrap_original do |original, *args|
      built += 1
      original.call(*args)
    end

    one_at_a_time = claims.to_h { |c| [ c.id, models.to_h { |m| [ m.id, Scoring::Score.call(c, seq, m).trace_hash ] } ] }
    ClaimScore.delete_all
    built = 0
    Scoring::Score.rescore(claims.map { |c| Claim.find(c.id) }, seq, models)

    expect(built).to eq(claims.size), "#{built} inputs built for #{claims.size} claims under #{models.size} models"
    # Same bytes, whichever way round it was done (Invariant 4).
    claims.each do |claim|
      models.each do |model|
        row = ClaimScore.find_by(claim_id: claim.id, scoring_model_id: model.id)
        expect(row.trace_hash).to eq(one_at_a_time[claim.id][model.id])
      end
    end
  end
end
