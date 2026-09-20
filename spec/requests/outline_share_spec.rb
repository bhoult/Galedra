require "rails_helper"

RSpec.describe "Sharing and following an outline (Stage 22)", type: :request do
  include LedgerHelpers
  include GraphHelpers
  before { release_models }

  def outline(pair, source, nodes)
    result = append(action_type: "CREATE_SECTION", key_pair: pair, payload: { "source_id" => source.id, "sections" => nodes })
    Section.find(Ledger::Ids.derive(result.contribution.id, "section", 0))
  end

  it "reports progress, a fixed share line, Open Graph tags, orders and filters the list, and flags unfinished outlines" do
    pair, = register_key
    source = create_source(pair, title: "Speech")
    root = outline(pair, source, [ { "heading" => "State of the union", "sections" => [ { "heading" => "Economy" }, { "heading" => "Health" } ] } ])
    economy, health = root.children.order(:position).to_a
    location = create_location(pair, source)
    a = create_claim(pair, "Unemployment fell to 3.5 percent.", type: "QUANTITATIVE", section_id: economy.id)
    b = create_claim(pair, "Prices rose 2 percent.", type: "QUANTITATIVE", section_id: economy.id)
    c = create_claim(pair, "Clinics opened in every county.", section_id: health.id)
    d = create_claim(pair, "Wait times fell.", section_id: health.id)
    e = create_claim(pair, "Coverage grew.", section_id: health.id)
    evidence = create_evidence(pair, location, statement: "The text states unemployment fell to 3.5 percent.")
    link_evidence(pair, evidence, a)
    seq = Contribution.maximum(:seq)

    progress = Sections::Progress.call(root, seq)
    expect(progress).to include(leaves: 2, leaves_extracted: 2, claims: 5, checked: 1, open_tasks: 0)
    line = Sections::Progress.share_line(root, seq, "http://www.example.com/sections/#{root.id}")
    expect(line).to eq("Checked in Galedra: State of the union · 5 claims · 0 self-checked · 0 independently checked · 5 insufficient evidence · http://www.example.com/sections/#{root.id}")

    get "/sections/#{root.id}"
    expect(response.body).to include('property="og:title" content="State of the union"')
    expect(response.body).to include("5 claims · 0 self-checked · 0 independently checked")
    expect(response.body).to include("2 of 2 leaves extracted")

    get "/weaknesses"
    expect(response.body).to include("unfinished outlines (1)").and include("State of the union")

    # A second outline with open work sorts first; a topic filter keeps only outlines with tagged claims.
    other_source = create_source(pair, title: "Other")
    other = outline(pair, other_source, [ { "heading" => "Podcast" } ])
    f = create_claim(pair, "A tagged claim.", section_id: other.id)
    append(action_type: "TAG_CLAIM", key_pair: pair, payload: { "claim_id" => f.id, "topics" => [ "technology/ai" ] })
    Tasks::Create.call(task_type: "QUALIFIER_CHECK", target: f, section_id: other.id)
    get "/sections"
    expect(response.body.index("Podcast")).to be < response.body.index("State of the union")
    get "/sections", params: { sort: "newest" }
    expect(response).to have_http_status(:ok)
    get "/sections", params: { topic: "technology/ai" }
    expect(response.body).to include("Podcast")
    expect(response.body).not_to include("State of the union")
    get "/sections", params: { topic: "health/vaccines" }
    expect(response.body).not_to include("Podcast")
  end
end
