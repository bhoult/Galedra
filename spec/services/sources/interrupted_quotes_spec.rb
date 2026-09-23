require "rails_helper"

# Stage 36: a quotation interrupted by markup is not one that is missing.
RSpec.describe "Interrupted quotations (Stage 36)" do
  include LedgerHelpers
  include GraphHelpers
  before { release_models }

  Location = Struct.new(:id, :excerpt)
  let(:page_source) { Struct.new(:source_type).new("WEBSITE") }

  def finding(html, excerpt)
    Sources::Retrieve.findings(page_source, [ Location.new("l", excerpt) ], "<html><body><p>#{html}</p></body></html>", "text/html").first
  end

  # Acceptance 1, the case in bug report 33349d5d. The first form is the one the
  # stage was planned from; the second is what qz.com actually serves, fetched
  # 2026-09-23 — a React comment and a space before the chip — and the first
  # version of this rule matched the plan and missed the page.
  it "finds a passage a ticker chip interrupts, and says that is what happened" do
    expect(finding(%(Nvidia<a href="/quote/NVDA">$NVDA</a>'s equity investments in AI companies), "Nvidia's equity investments"))
      .to eq("location_id" => "l", "found" => "INTERRUPTED", "rendering" => "INLINE_ELIDED")
    served = %(<p>Nvidia<!-- --> <a class="inline-flex" href="/quote/NVDA">$NVDA</a>&#x27;s equity investments in AI companies ) +
             %(<a href="https://www.cnbc.com/x">hit $99 billion</a> as of July 26, a figure the company disclosed</p>)
    expect(finding(served, "Nvidia's equity investments in AI companies hit $99 billion as of July 26")["found"]).to eq("INTERRUPTED")
  end

  # Acceptance 2: the stage must not make the verifier lie in the other direction.
  # Each condition in Sources::Retrieve.elision has a case here that it alone
  # refuses, so loosening any one of them fails exactly one line.
  it "never lets a quotation span words the page contains" do
    expect(finding("the study found <a>no evidence of</a> higher productivity", "the study found higher productivity")["found"])
      .to eq("NOT_FOUND"), "the stage's own example"
    expect(finding("it costs<a>$5 more</a>.", "it costs.")["found"])
      .to eq("NOT_FOUND"), "a phrase is not a chip (condition 1)"
    expect(finding("the study found <a>no</a>.", "the study found.")["found"])
      .to eq("NOT_FOUND"), "a word is part of the sentence, however it is marked up (condition 2)"
    expect(finding("output rose <sup>12</sup> sharply", "output rose sharply")["found"])
      .to eq("NOT_FOUND"), "a number spaced on both sides may be one the sentence says (condition 3)"
    expect(finding("the 1<sup>2</sup>0 cases", "the 10 cases")["found"])
      .to eq("NOT_FOUND"), "leaving it out would fuse two words into one (condition 4)"
  end

  # Acceptance 3.
  it "closes a passage our own space insertion broke, and calls it normalized" do
    expect(finding("the <em>very</em> best", "the very best")["found"]).to eq("VERBATIM")
    expect(finding("an extra<em>ordinary</em> result", "an extraordinary result"))
      .to eq("location_id" => "l", "found" => "NORMALIZED", "rendering" => "INLINE_JOINED")
  end

  it "says a transcription it cannot find was not read, rather than not found" do
    spoken = Struct.new(:id, :excerpt, :locator_type)
    body = "<html><body><p>A video page with a title and a description.</p></body></html>"
    found = ->(text) { Sources::Retrieve.findings(page_source, [ spoken.new("t", text, "TRANSCRIPTION") ], body, "text/html").first["found"] }
    expect(found.call("We should have more kids.")).to eq("NOT_READ")
    expect(found.call("a title and a description")).to eq("VERBATIM"), "a transcription that is on the page still says so"
  end

  it "leaves the served reading's findings exactly as they were" do
    expect(finding("A plain sentence.", "A plain sentence.")).to eq("location_id" => "l", "found" => "VERBATIM")
    expect(finding("Never here.", "Something else.")).to eq("location_id" => "l", "found" => "NOT_FOUND")
    footnoted = finding("Productivity rose<sup>12</sup>.", "Productivity rose.")
    expect(footnoted["found"]).to eq("INTERRUPTED")
  end

  it "records the finding through a retrieval, labels the card, and replays" do
    pair, = register_key
    payload = { "source_type" => "WEBSITE", "title" => "A page", "canonical_uri" => "https://example.org/nvidia", "retrieved_at" => Time.now.utc.iso8601 }
    source = row_for(append(action_type: "CREATE_SOURCE", key_pair: pair, payload: payload), "source", Source)
    excerpt = "Nvidia's equity investments in AI companies"
    location = row_for(append(action_type: "CREATE_SOURCE_LOCATION", key_pair: pair,
                              payload: { "source_id" => source.id, "locator_type" => "QUOTE", "locator" => {}, "excerpt" => excerpt, "excerpt_hash" => Crypto::Hashing.bytes(excerpt) }), "location", SourceLocation)
    claim = create_claim(pair, "Nvidia's equity investments in AI companies reached $99 billion.", type: "QUANTITATIVE")
    link_evidence(pair, create_evidence(pair, location), claim)

    body = %(<html><body><p>Nvidia<a href="/quote/NVDA">$NVDA</a>'s equity investments in AI companies hit $99 billion.</p></body></html>)
    fetcher = Object.new
    fetcher.define_singleton_method(:get) { |uri| Sources::Retrieve::Response.new(status: "FETCHED", media_type: "text/html", body: body, final_url: uri.to_s) }
    contribution = Sources::Retrieve.call(source, fetcher: fetcher)

    row = SourceRetrieval.find(Ledger::Ids.derive(contribution.id, "retrieval"))
    expect(row.finding_for(location.id)).to eq("INTERRUPTED")
    expect(row.rendering_for(location.id)).to eq("INLINE_ELIDED")

    labels = Cards::ClaimCard.call(claim, Contribution.maximum(:seq), Scoring::Registry.default_model)[:labels]
    expect(labels.join(" ")).to include("markup interrupts the sentence").and include("Every quoted passage was confirmed")
    expect(labels.join(" ")).not_to include("was not found")

    before = Ledger::TableDigest.projections
    Ledger::Replay.call
    expect(Ledger::TableDigest.projections).to eq(before)
  end

  it "refuses a rendering outside the closed list" do
    pair, = register_key
    payload = { "source_type" => "WEBSITE", "title" => "A page", "canonical_uri" => "https://example.org/x", "retrieved_at" => Time.now.utc.iso8601 }
    source = row_for(append(action_type: "CREATE_SOURCE", key_pair: pair, payload: payload), "source", Source)
    location = row_for(append(action_type: "CREATE_SOURCE_LOCATION", key_pair: pair,
                              payload: { "source_id" => source.id, "locator_type" => "QUOTE", "locator" => {}, "excerpt" => "x", "excerpt_hash" => Crypto::Hashing.bytes("x") }), "location", SourceLocation)
    expect {
      append(action_type: "RETRIEVE_SOURCE", key_pair: Crypto::SystemKey.key_pair, custody: Crypto::Custody::SYSTEM,
             payload: { "source_id" => source.id, "outcome" => "FETCHED", "fetched_at" => Time.now.utc.iso8601, "content_hash" => Crypto::Hashing.bytes("x"),
                        "content_length" => 1, "media_type" => "text/html", "final_url" => "https://example.org/x",
                        "excerpts" => [ { "location_id" => location.id, "found" => "INTERRUPTED", "rendering" => "GUESSED" } ] })
    }.to raise_error(Ledger::Rejected) { |e| expect(e.errors.first[:path]).to end_with(".rendering") }
  end

  # Acceptance 6: Galedra's own fetch has never been a scoring input in either
  # direction, and a new finding must not become one.
  it "keeps retrieval out of scoring and audits" do
    files = Dir[Rails.root.join("app/services/{scoring,audits}/**/*.rb")]
    expect(files).not_to be_empty
    expect(files.select { |f| File.read(f).include?("SourceRetrieval") }).to eq([])
  end
end
