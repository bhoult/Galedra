require "rails_helper"

# A badge at every level of an outline, and a score wherever there is enough
# evidence for one (owner request, 2026-09-23). The badge is the icon alone;
# what it means, how many claims it was read from and the figure are on hover,
# and none of it is a score for the speaker (06 §6, Article XVIII).
RSpec.describe "Readings at every level of an outline", type: :request do
  include LedgerHelpers
  include GraphHelpers
  before { release_models }

  it "reads each parent from the claims under it, and gives a figure only when every checkable claim has one" do
    pair, = register_key
    source = create_source(pair, title: "A speech")
    result = append(action_type: "CREATE_SECTION", key_pair: pair,
                    payload: { "source_id" => source.id, "sections" => [ { "heading" => "A speech", "sections" => [ { "heading" => "Part one" }, { "heading" => "Part two" } ] } ] })
    root, one, two = Section.where(contribution_id: result.contribution.id).order(:depth, :position).to_a
    supported = create_claim(pair, "A claim with direct support.", section_id: one.id)
    # From another source: evidence from the outline's own source is provenance,
    # not corroboration, and would weigh nothing (Stage 35).
    link_evidence(pair, create_evidence(pair, create_location(pair, create_source(pair, title: "A report"))), supported)
    create_claim(pair, "A claim nothing bears on.", section_id: two.id)
    seq = Contribution.maximum(:seq)

    tree = Sections::Tree.call(root, seq)
    part_one = tree[:children].find { |c| c[:section].id == one.id }
    part_two = tree[:children].find { |c| c[:section].id == two.id }
    expect(part_one[:verdict][:figure]).to be_present
    expect(part_two[:verdict][:figure]).to be_nil
    expect(part_two[:verdict][:badge]).to eq(:not_checked)
    # The root's figure is the average of the scored claims under it, once at
    # least half of its checkable claims have a score: here one of two.
    expect(tree[:verdict][:counts][:claims]).to eq(2)
    expect(tree[:verdict][:figure]).to eq(part_one[:verdict][:figure])
    expect(tree[:verdict][:stated]).to include("the average of 1 of 2 checkable claims")

    get "/sections/#{root.id}"
    marks = Nokogiri::HTML(response.body).css(".reading-mark")
    expect(marks).not_to be_empty
    expect(marks.map { |m| m["title"] }).to include(a_string_including("read from the 1 claim under this section"))
    expect(marks.map { |m| m["title"] }).to all(a_string_including("provisional until audited"))
    expect(marks.map { |m| m["title"] }.join).not_to match(/speaker (is|was)|the speaker's score/i)
    expect(response.body).not_to include("state_mark")

    get "/api/v1/sections/#{root.id}"
    expect(response.parsed_body.dig("section", "reading", "label")).to be_present
  end
end

RSpec.describe Investigations::Verdict do
  before { release_models }

  let(:result) { Struct.new(:assessment_state, :probability) }

  def reading(pairs, collection:)
    results = pairs.map { |state, p| result.new(state, p) }
    described_class.summarize(results, 10, Scoring::Registry.default_model, collection: collection)
  end

  # Measured on the development node: an outline of 54 claims, 36 holding and
  # 6 against, read as "Leans against" under the one-statement rule. A
  # collection's badge now comes from its average score, through the model's
  # own state bands, so the badge and the number beside it always agree.
  it "reads a single statement by its weakest part, and a collection by its average score" do
    pairs = Array.new(36) { [ "SUPPORTED", "0.8500" ] } + Array.new(6) { [ "CONTRADICTED", "0.1500" ] } + Array.new(9) { [ "INSUFFICIENT_EVIDENCE", nil ] }
    expect(reading(pairs, collection: false)[:badge]).to eq(:leans_against)
    collected = reading(pairs, collection: true)
    expect(collected[:figure]).to eq("0.7500")
    expect(collected[:badge]).to eq(:leans_supported)

    expect(reading([ [ "SUPPORTED", "0.9500" ], [ "SUPPORTED", "0.9300" ] ], collection: true)[:badge]).to eq(:strongly_supported)
    expect(reading([ [ "SUPPORTED", "0.8500" ], [ "LEANS_SUPPORTED", "0.7700" ] ], collection: true)[:badge]).to eq(:mostly_supported)
    expect(reading([ [ "UNRESOLVED", "0.5000" ] ], collection: true)[:badge]).to eq(:mixed)
    expect(reading([ [ "CONTRADICTED", "0.1500" ], [ "LEANS_CONTRADICTED", "0.2000" ] ], collection: true)[:badge]).to eq(:mostly_against)
    expect(reading([ [ "CONTRADICTED", "0.0500" ] ], collection: true)[:badge]).to eq(:strongly_against)
    # Too little scored for an average: not checked, whatever the one score says.
    expect(reading([ [ "SUPPORTED", "0.9500" ], [ "INSUFFICIENT_EVIDENCE", nil ], [ "INSUFFICIENT_EVIDENCE", nil ] ], collection: true)[:badge]).to eq(:not_checked)
    expect(reading([ [ "NOT_APPLICABLE", nil ] ], collection: true)[:badge]).to eq(:not_checkable)
  end
end
