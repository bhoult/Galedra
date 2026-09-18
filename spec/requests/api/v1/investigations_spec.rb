require "rails_helper"

RSpec.describe "Record an investigation (Stage 13)", type: :request do
  before { release_models }

  let(:headers) { { "CONTENT_TYPE" => "application/json" } }
  let!(:token) { Assistants::Connect.call(name: "Claude", provider: "anthropic").last }

  def post_bundle(bundle, tok = token)
    post "/api/v1/investigations", params: bundle.to_json, headers: headers.merge("Authorization" => "Bearer #{tok}")
    response
  end

  def fixture_bundle
    JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).tap do |b|
      b.delete("_about")
      b["sources"].each { |s| s["retrieved_at"] = Time.now.utc.iso8601 }
    end
  end

  it "records a social post, two claims, two excerpts, and their links in order, and returns a card and URL per claim (#1)" do
    before = Contribution.count
    post_bundle(fixture_bundle)
    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body["recorded"]).to be(true)
    expect(body["contributions"]).to eq(11)
    expect(body["tasks_opened"]).to eq(6)

    kinds = Contribution.order(:seq).offset(before).where.not(action_type: "ACCEPT").pluck(:action_type)
    expect(kinds).to eq(%w[CREATE_SOURCE CREATE_SOURCE CREATE_SOURCE_LOCATION CREATE_SOURCE_LOCATION CREATE_CLAIM CREATE_CLAIM CREATE_EVIDENCE CREATE_EVIDENCE LINK_EVIDENCE LINK_EVIDENCE LINK_EVIDENCE])
    ban, narrow = body["claims"]
    expect(ban).to include("handle" => "ban", "created" => true)
    expect(ban["url"]).to eq("http://www.example.com/claims/#{ban['id']}")
    expect(ban.dig("card", "headline")).to eq("Leans contradicted").or eq("Contradicted")
    expect(ban.dig("card", "plain", "headline")).to match(/evidence (leans|goes) against/)
    expect(ban.dig("card", "plain", "say_instead")).to eq("Brackenridge prohibits cycling on the Market Street pedestrian mall on Saturday daytimes during the December market season.").or start_with("This has not held up:")
    expect(narrow.dig("card", "headline")).to eq("Supported")
    expect(narrow.dig("card", "labels")).to include(a_string_starting_with("Not yet independently audited"))

    source = Source.find(body["ids"]["post"])
    expect(source.source_type).to eq("SOCIAL_POST")
    expect(source).to be_by_reference
    expect(source.content).to be_nil
    expect(Task.where(target_id: ban["id"]).pluck(:task_type)).to contain_exactly("OPPOSING_EVIDENCE_SEARCH", "QUALIFIER_CHECK", "EVIDENCE_VERIFICATION")
  end

  it "appends nothing when the second link is invalid (#2) and rejects a malformed bundle before touching the log" do
    bundle = fixture_bundle
    bundle["links"][1]["direction"] = "SUPPORTS_A_LOT"
    count = Contribution.count
    post_bundle(bundle)
    expect(response).to have_http_status(422)
    expect(response.parsed_body["errors"].first["path"]).to eq("$.links[1].direction")
    expect(Contribution.count).to eq(count)

    bundle = fixture_bundle
    bundle["links"][1]["claim"] = "narrow"
    bundle["evidence"][1]["excerpt"] = "post_text"
    bundle["claims"][1]["text"] = "x" * (Claim::MAX_TEXT_CHARS + 1)
    post_bundle(bundle)
    expect(response).to have_http_status(422)
    expect(Contribution.count).to eq(count)
    expect(Source.count).to eq(0)
  end

  it "returns the demo statistic under existing and creates no twin when the assistant attaches (#3)" do
    graph = build_public_demo
    c2 = graph.claims["C2"]
    bundle = fixture_bundle
    bundle["claims"] = [ { "handle" => "stat", "text" => "62% of remote workers report higher productivity.", "type" => "QUANTITATIVE" } ]
    bundle["links"] = [ { "evidence" => "motion", "claim" => "stat", "direction" => "NEUTRAL", "strength" => "CONTEXT_ONLY", "steps" => 0 } ]
    count = Contribution.count

    post_bundle(bundle)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body["recorded"]).to be(false)
    expect(response.parsed_body.dig("existing", "stat").first).to include("id" => c2.id, "url" => "http://www.example.com/claims/#{c2.id}")
    expect(Contribution.count).to eq(count)

    bundle["claims"] = [ { "handle" => "stat", "attach_to" => c2.id } ]
    post_bundle(bundle)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body["claims"].first).to include("id" => c2.id, "created" => false)
    expect(Claim.where(canonical_text: "62% of remote workers report higher productivity.").count).to eq(1)
    expect(EvidenceClaimLink.where(claim_id: c2.id).count).to be > 0
    expect(Task.where(target_id: c2.id, created_by_contributor_id: AssistantToken.last.agent_contributor_id)).to be_empty
  end

  it "renders a source held by reference with the link, the hash, and the excerpt, never page text, and replay reproduces it (#4)" do
    post_bundle(fixture_bundle)
    source = Source.find(response.parsed_body["ids"]["minutes"])
    get "/sources/#{source.id}"
    expect(response.body).to include("https://brackenridge.example/council/minutes/2026-09-03")
    expect(response.body).to include(source.content_hash)
    expect(response.body).to include("held by reference")
    expect(response.body).to include("Motion 14 carried")
    expect(response.body).not_to include("Stored text")

    get "/api/v1/sources/#{source.id}"
    expect(response.parsed_body["source"]).to include("content" => nil, "canonical_uri" => "https://brackenridge.example/council/minutes/2026-09-03", "retrieval_pending" => true)

    before = Ledger::TableDigest.projections
    Ledger::Replay.call
    expect(Ledger::TableDigest.projections).to eq(before)
  end

  it "gives plain say_instead only when the graph supports one (#5)" do
    curator, = register_key(display_name: "Curator")
    model = Scoring::Registry.default_model
    bare = create_claim(curator, "Nothing bears on this yet.")
    seq = Contribution.maximum(:seq)
    card = Cards::ClaimCard.call(bare, seq, model)
    expect(card[:plain]).to eq(headline: "Nobody has checked this yet.", say_instead: nil)

    normative = create_claim(curator, "Everyone should cycle.", type: "NORMATIVE")
    expect(Cards::ClaimCard.call(normative, Contribution.maximum(:seq), model)[:plain][:headline]).to include("opinion")

    graph = build_public_demo
    s5 = graph.checkpoints["S5"]
    plain = Cards::ClaimCard.call(graph.claims["C2"], s5, model)[:plain]
    expect(plain[:headline]).to start_with("The evidence is mixed")
    expect(plain[:say_instead]).to eq(graph.claims["C3"].canonical_text)
    expect(Cards::ClaimCard.call(graph.claims["C4"], s5, model)[:plain][:headline]).to eq("The evidence leans against this.")
  end
end
