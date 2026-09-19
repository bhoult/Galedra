require "rails_helper"

RSpec.describe "Source retrieval by a trusted job (Stage 17)" do
  include LedgerHelpers
  include GraphHelpers

  # A fetcher with the real interface and canned pages, so no network is touched.
  class FakeFetcher
    Page = Struct.new(:status, :media_type, :body, :final_url)
    def initialize(pages) = @pages = pages
    def get(uri)
      page = @pages.fetch(uri.to_s) { Page.new("NOT_FOUND", nil, nil, uri.to_s) }
      raise Sources::Retrieve::Refused, uri.host if page.status == "REFUSED"
      raise Net::ReadTimeout if page.status == "TIMEOUT"

      Sources::Retrieve::Response.new(status: page.status, media_type: page.media_type, body: page.body, final_url: page.final_url || uri.to_s)
    end
  end

  def reference_source(pair, url:, excerpts:, type: "WEBSITE")
    payload = { "source_type" => type, "title" => "A page", "canonical_uri" => url, "retrieved_at" => Time.now.utc.iso8601 }
    source = row_for(append(action_type: "CREATE_SOURCE", key_pair: pair, payload: payload), "source", Source)
    locations = excerpts.map do |text|
      row_for(append(action_type: "CREATE_SOURCE_LOCATION", key_pair: pair,
                     payload: { "source_id" => source.id, "locator_type" => "QUOTE", "locator" => {}, "excerpt" => text, "excerpt_hash" => Crypto::Hashing.bytes(text) }), "location", SourceLocation)
    end
    [ source, locations ]
  end

  let(:html) { "<html><head><title>T</title><style>p{}</style><script>alert(1)</script></head><body><p>The quick “brown” fox&nbsp;jumps.</p><p>Second   paragraph here.</p></body></html>" }

  it "records what a fetch found, one VERBATIM and one NORMALIZED and one NOT_FOUND excerpt, shown on the page and API, and replays (#1)" do
    pair, = register_key
    source, locations = reference_source(pair, url: "https://example.org/page", excerpts: [ "Second paragraph here.", "the quick \"brown\" fox jumps.", "Never on the page." ])
    fetcher = FakeFetcher.new("https://example.org/page" => FakeFetcher::Page.new("FETCHED", "text/html", html, "https://example.org/page"))

    contribution = Sources::Retrieve.call(source, fetcher: fetcher)
    expect(contribution.action_type).to eq("RETRIEVE_SOURCE")
    expect(contribution.contributor).to be_system
    row = SourceRetrieval.find(Ledger::Ids.derive(contribution.id, "retrieval"))
    expect(row).to have_attributes(outcome: "FETCHED", content_hash: Crypto::Hashing.bytes(html.b), content_length: html.bytesize, media_type: "text/html", final_url: "https://example.org/page")
    expect(row.excerpts.map { |e| e["found"] }).to eq(%w[VERBATIM NORMALIZED NOT_FOUND])
    expect(row.excerpts.map { |e| e["location_id"] }).to eq(locations.map(&:id))
    expect(source.reload.retrieval_pending).to be(false)
    expect(contribution.payload).not_to have_key("content")

    expect(Sources::Retrieve.call(source, fetcher: fetcher)).to be_nil
    expect(Sources::Retrieve.call(source, fetcher: fetcher, force: true)).not_to be_nil
    expect(SourceRetrieval.where(source_id: source.id).count).to eq(2)

    presented = Graph::Presenter.source(source)
    expect(presented[:retrievals].first).to include(outcome: "FETCHED", content_hash: row.content_hash)

    before = Ledger::TableDigest.projections
    Ledger::Replay.call
    expect(Ledger::TableDigest.projections).to eq(before)
    expect(Ledger::Verify.call).to be_ok
  end

  it "refuses private, loopback, and link-local addresses before connecting, and on a redirect that lands there (#2)" do
    resolver = Class.new do
      def self.getaddresses(host)
        { "internal.example" => [ "10.0.0.5" ], "loop.example" => [ "127.0.0.1" ], "link.example" => [ "169.254.169.254" ], "six.example" => [ "fd00::1" ], "public.example" => [ "93.184.216.34" ] }.fetch(host, [])
      end
    end
    %w[internal.example loop.example link.example six.example].each do |host|
      expect { Sources::Retrieve.refuse_private!(host, resolver: resolver) }.to raise_error(Sources::Retrieve::Refused)
    end
    expect(Sources::Retrieve.refuse_private!("public.example", resolver: resolver)).to eq([ "93.184.216.34" ])

    pair, = register_key
    source, = reference_source(pair, url: "https://internal.example/x", excerpts: [ "a" ])
    contribution = Sources::Retrieve.call(source, fetcher: FakeFetcher.new("https://internal.example/x" => FakeFetcher::Page.new("REFUSED")))
    expect(contribution.payload["outcome"]).to eq("REFUSED")
    expect(SourceRetrieval.last.outcome).to eq("REFUSED")
    expect(source.reload.retrieval_pending).to be(true)
  end

  it "records TOO_LARGE, TIMEOUT, NOT_FOUND, BLOCKED, and UNSUPPORTED outcomes once each, and honours robots.txt (#3)" do
    pair, = register_key
    pages = {
      "https://big.example/" => FakeFetcher::Page.new("TOO_LARGE"), "https://slow.example/" => FakeFetcher::Page.new("TIMEOUT"),
      "https://gone.example/" => FakeFetcher::Page.new("NOT_FOUND"), "https://closed.example/" => FakeFetcher::Page.new("BLOCKED")
    }
    fetcher = FakeFetcher.new(pages)
    outcomes = pages.keys.map do |url|
      source, = reference_source(pair, url: url, excerpts: [ "x" ])
      Sources::Retrieve.call(source, fetcher: fetcher).payload["outcome"]
    end
    expect(outcomes).to eq(%w[TOO_LARGE TIMEOUT NOT_FOUND BLOCKED])
    ftp, = reference_source(pair, url: "ftp://files.example/x", excerpts: [ "x" ])
    expect(Sources::Retrieve.call(ftp, fetcher: fetcher).payload["outcome"]).to eq("UNSUPPORTED")

    robots = "User-agent: *\nDisallow: /private\nAllow: /private/ok\n\nUser-agent: galedra\nDisallow: /nope\n"
    expect(Sources::Retrieve.robots_disallow?(robots, "/nope/x")).to be(true)
    expect(Sources::Retrieve.robots_disallow?(robots, "/private")).to be(false)
    expect(Sources::Retrieve.robots_disallow?("User-agent: *\nDisallow: /private\nAllow: /private/ok\n", "/private/x")).to be(true)
    expect(Sources::Retrieve.robots_disallow?("User-agent: *\nDisallow: /private\nAllow: /private/ok\n", "/private/ok/y")).to be(false)
    expect(Sources::Retrieve.robots_disallow?("", "/anything")).to be(false)
  end

  it "hashes an IMAGE as bytes with transcriptions UNSUPPORTED, and never fetches stored content or sources created inside a task (#4)" do
    pair, = register_key
    image_payload = { "source_type" => "IMAGE", "title" => "Meme", "canonical_uri" => "https://img.example/m.png", "retrieved_at" => Time.now.utc.iso8601 }
    image = row_for(append(action_type: "CREATE_SOURCE", key_pair: pair, payload: image_payload), "source", Source)
    location = row_for(append(action_type: "CREATE_SOURCE_LOCATION", key_pair: pair, payload: { "source_id" => image.id, "locator_type" => "TRANSCRIPTION", "locator" => {}, "excerpt" => "words on the image", "excerpt_hash" => Crypto::Hashing.bytes("words on the image") }), "location", SourceLocation)
    bytes = "\x89PNG\r\n\x1a\n".b + ("x" * 100).b
    contribution = Sources::Retrieve.call(image, fetcher: FakeFetcher.new("https://img.example/m.png" => FakeFetcher::Page.new("FETCHED", "image/png", bytes)))
    expect(contribution.payload).to include("outcome" => "FETCHED", "content_hash" => Crypto::Hashing.bytes(bytes), "media_type" => "image/png")
    expect(contribution.payload["excerpts"]).to eq([ { "location_id" => location.id, "found" => "UNSUPPORTED" } ])

    stored = create_source(pair)
    expect(Sources::Retrieve.call(stored, fetcher: FakeFetcher.new({}))).to be_nil
    expect { append(action_type: "RETRIEVE_SOURCE", key_pair: Crypto::SystemKey.key_pair, custody: Crypto::Custody::SYSTEM,
                    payload: { "source_id" => stored.id, "fetched_at" => Time.now.utc.iso8601, "outcome" => "NOT_FOUND" }) }.to raise_error(Ledger::Rejected)
    expect { append(action_type: "RETRIEVE_SOURCE", key_pair: pair, payload: { "source_id" => image.id, "fetched_at" => Time.now.utc.iso8601, "outcome" => "NOT_FOUND" }) }.to raise_error(Ledger::Rejected) { |e| expect(e.errors.first[:code]).to eq("NOT_AUTHORIZED") }

    with_env("LEDGER_RETRIEVAL" => "on") do
      expect { reference_source(pair, url: "https://enqueue.example/", excerpts: []) }.to have_enqueued_job(RetrieveSourceJob)
      expect { create_source(pair, title: "stored") }.not_to have_enqueued_job(RetrieveSourceJob)
      expect { Ledger::Replay.call }.not_to have_enqueued_job(RetrieveSourceJob)
    end
    with_env("LEDGER_RETRIEVAL" => nil) do
      expect { reference_source(pair, url: "https://quiet.example/", excerpts: []) }.not_to have_enqueued_job(RetrieveSourceJob)
    end
  end

  it "leaves every score unchanged, and shows a NOT_FOUND finding on the card and the verification task (#5)" do
    release_models
    pair, = register_key
    source, locations = reference_source(pair, url: "https://example.org/claim", excerpts: [ "Remote work raises output by 12%." ])
    claim = create_claim(pair, "Remote work raises output by 12%.", type: "QUANTITATIVE")
    evidence = create_evidence(pair, locations.first, statement: "The page says remote work raises output by 12%.")
    link_evidence(pair, evidence, claim)
    seq = Contribution.maximum(:seq)
    model = Scoring::Registry.default_model
    before = Scoring::Score.call(claim, seq, model)
    task = Tasks::Create.call(task_type: "EVIDENCE_VERIFICATION", target: claim, location: locations.first)

    contribution = Sources::Retrieve.call(source, fetcher: FakeFetcher.new("https://example.org/claim" => FakeFetcher::Page.new("FETCHED", "text/html", "<p>Something else entirely.</p>")))
    expect(SourceRetrieval.find(Ledger::Ids.derive(contribution.id, "retrieval")).excerpts.first["found"]).to eq("NOT_FOUND")

    after_seq = Contribution.maximum(:seq)
    after = Scoring::Score.call(claim, after_seq, model)
    expect(after.assessment_state).to eq(before.assessment_state)
    expect(after.probability).to eq(before.probability)
    expect(after.review_checklist).to eq(before.review_checklist)
    expect(ReputationEvent.count).to eq(0)

    card = Cards::ClaimCard.call(claim, after_seq, model)
    expect(card[:labels]).to include("A quoted passage was not found on the page when Galedra fetched it.")
    assignment = Struct.new(:lease_expires_at).new(1.hour.from_now)
    presented = Tasks::Answer.present(task, assignment, base_url: "http://x")
    expect(presented[:context]["retrieval"]).to include("found" => "NOT_FOUND")
    expect(task.packet.dig("context", "retrieval")).to be_nil
  end
end
