require "rails_helper"

RSpec.describe "The whole text, readable in Galedra (Stage 30)", type: :request do
  include LedgerHelpers
  include GraphHelpers
  before { release_models }

  let(:pair) { register_key.first }
  # Held by reference: no content stored, which is the case an outline is for.
  let(:source) do
    result = append(action_type: "CREATE_SOURCE", key_pair: pair,
                    payload: { "source_type" => "VIDEO", "title" => "An episode", "canonical_uri" => "https://example.org/ep", "retrieved_at" => Time.now.utc.iso8601 })
    Source.find(Ledger::Ids.derive(result.contribution.id, "source"))
  end

  # Built directly: the graph helper slices the source's stored content, and a
  # source held by reference has none.
  def location(type, text, start:, finish:)
    result = append(action_type: "CREATE_SOURCE_LOCATION", key_pair: pair,
                    payload: { "source_id" => source.id, "locator_type" => type,
                               "locator" => { "start" => start, "end" => finish },
                               "excerpt" => text, "excerpt_hash" => Crypto::Hashing.bytes(text) })
    SourceLocation.find(Ledger::Ids.derive(result.contribution.id, "location"))
  end

  def anchor(text, start:, finish:) = location("TIME_RANGE", text, start: start, finish: finish)
  def reading(text, start:, finish:) = location("TRANSCRIPTION", text, start: start, finish: finish)

  it "holds a leaf's text, composes a branch from its leaves, and shows the whole thing at the root" do
    one = reading("First paragraph of the opening.\n\nSecond paragraph of the opening.", start: "00:00:00", finish: "00:03:00")
    two = reading("What the second leaf actually says at length.", start: "00:03:00", finish: "00:06:00")
    result = append(action_type: "CREATE_SECTION", key_pair: pair, payload: {
      "source_id" => source.id,
      "sections" => [ { "heading" => "Root", "sections" => [
        { "heading" => "First part", "location_id" => anchor("First paragraph", start: "00:00:00", finish: "00:03:00").id, "reading_location_id" => one.id },
        { "heading" => "Second part", "location_id" => anchor("What the second", start: "00:03:00", finish: "00:06:00").id, "reading_location_id" => two.id }
      ] } ] })
    root = Section.find(Ledger::Ids.derive(result.contribution.id, "section", 0))
    first, second = root.children.order(:position).to_a

    # A leaf holds its own text, in full.
    get "/sections/#{first.id}"
    expect(response.body).to include("Second paragraph of the opening.")
    expect(response.body).not_to include("What the second leaf actually says")

    # A branch has no text of its own; it is its leaves in order.
    get "/sections/#{root.id}"
    body = response.body
    expect(body).to include("First paragraph of the opening.").and include("What the second leaf actually says")
    expect(body.index("First paragraph of the opening.")).to be < body.index("What the second leaf actually says")
    expect(body).to include("The whole text")

    # Nothing is stored twice: emptying a leaf empties what the root shows.
    seq = Contribution.maximum(:seq)
    expect(Sections::Text.call(root, seq).map(&:text)).to eq([ one.excerpt, two.excerpt ])
    expect(Sections::Text.call(first, seq).map(&:text)).to eq([ one.excerpt ])
  end

  it "refuses to take cleaned text as a quotation, and keeps it out of the source check" do
    # A QUOTE is the kind retrieval looks for in the fetched source; an
    # outline's time-range anchors are located by their range instead.
    quoted = location("QUOTE", "The exact opening words", start: "00:00:00", finish: "00:03:00")

    # A reading must be a TRANSCRIPTION. Hashing cleaned text as a quotation is
    # how edited speech would end up carrying a real speaker's name.
    expect_rejected("SCHEMA_INVALID") do
      append(action_type: "CREATE_SECTION", key_pair: pair, payload: {
        "source_id" => source.id,
        "sections" => [ { "heading" => "Root", "sections" => [ { "heading" => "A part", "reading_location_id" => quoted.id } ] } ] })
    end

    # A quotation is still checked; a section's reading is left out, although it
    # carries the same locator type, because it was never a quotation.
    text = reading("Cleaned up, with paragraphs the source never had.", start: "00:00:00", finish: "00:03:00")
    append(action_type: "CREATE_SECTION", key_pair: pair, payload: {
      "source_id" => source.id,
      "sections" => [ { "heading" => "Root", "sections" => [ { "heading" => "A part", "location_id" => quoted.id, "reading_location_id" => text.id } ] } ] })

    page = Sources::Retrieve::Response.new(status: "FETCHED", media_type: "text/html", body: "<p>The exact opening words and more.</p>", final_url: source.canonical_uri)
    fetcher = Class.new { def initialize(p) = @p = p; def get(_uri) = @p }.new(page)
    contribution = Sources::Retrieve.call(source, fetcher: fetcher)
    checked = contribution.payload["excerpts"]
    expect(checked.map { |e| e["location_id"] }).to include(quoted.id)
    expect(checked.map { |e| e["location_id"] }).not_to include(text.id), "a reading is not a quotation and is never checked against the source"
    expect(checked.find { |e| e["location_id"] == quoted.id }["found"]).to eq("VERBATIM")
  end
end
