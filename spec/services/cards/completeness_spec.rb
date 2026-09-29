require "rails_helper"

# The completeness meter beside a claim's score (owner request, 2026-09-29):
# a segment per review-checklist item, counted when the score counts it, own
# when only the claim's author did the check, and empty otherwise.
RSpec.describe Cards::Completeness do
  before { release_models }

  let(:model) { Scoring::Registry.default_model }

  def statements
    n = 0
    counter = ->(*, payload) { n += 1 unless payload[:name].to_s == "SCHEMA" || payload[:sql].to_s.start_with?("BEGIN", "COMMIT") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    n
  end

  # A claim whose author checked it for opposing evidence through their own
  # agent (self-performed), and which somebody else checked for qualifiers.
  def checked_claim(text)
    author_pair, author_agent_pair, _, author_delegation = principal_with_agent
    claim = create_claim(author_pair, text, type: "OBSERVATIONAL")
    submit_result(author_agent_pair, create_task("OPPOSING_EVIDENCE_SEARCH", claim), delegation: author_delegation, outcome: "NONE_FOUND", ops: [])
    _, other_agent_pair, _, other_delegation = principal_with_agent
    submit_result(other_agent_pair, create_task("QUALIFIER_CHECK", claim), delegation: other_delegation, outcome: "NONE_MATERIAL", ops: [])
    claim
  end

  it "keeps a check by the claim's author apart from one the score counts" do
    claim = checked_claim("The harbour closed for dredging in May.")
    seq = Contribution.maximum(:seq)
    result = Scoring::Score.call(claim, seq, model)
    meter = described_class.for_results({ claim.id => result }, seq)[claim.id]

    states = meter[:segments].to_h { |s| [ s[:item], s[:state] ] }
    expect(states["qualifiers_reviewed"]).to eq(:counted), "somebody else's check is in review coverage"
    expect(states["opposing_search_done"]).to eq(:own), "the author's own check is shown, and not counted"
    expect(states["primary_source_reviewed"]).to eq(:none)
    expect(meter).to include(total: 4, counted: 1, own: 1)
    expect(meter[:counted]).to eq(result.review_checklist.count { |_, v| v["ok"] }), "counted is exactly what review_coverage counts"

    whole = described_class.total([ meter, described_class.meter(nil) ])
    expect(whole).to include(claims: 2, total: 4, counted: 1, own: 1, done_percent: 50, counted_percent: 25)
  end

  it "asks the same number of statements for one claim or many" do
    one = checked_claim("The first ferry ran late.")
    seq = Contribution.maximum(:seq)
    single = statements { described_class.own_checks([ one.id ], seq) }
    many = 4.times.map { |i| checked_claim("Ferry #{i} ran late.") }
    seq = Contribution.maximum(:seq)
    expect(statements { described_class.own_checks([ one.id ] + many.map(&:id), seq) }).to eq(single)
  end
end
