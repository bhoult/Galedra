require "rails_helper"

RSpec.describe "Sections and placements in the log (Stage 20)", type: :request do
  include LedgerHelpers
  include GraphHelpers
  before { release_models }

  let(:password) { "correct horse battery staple" }

  def outline(pair, source, nodes, parent: nil)
    payload = parent ? { "parent_section_id" => parent.id, "sections" => nodes } : { "source_id" => source.id, "sections" => nodes }
    result = append(action_type: "CREATE_SECTION", key_pair: pair, payload: payload)
    Section.where(contribution_id: result.contribution.id).order(:created_seq, :depth, :position).to_a
  end

  it "creates a subtree in one write with preorder ids, extends it, renders it, and refuses bad shapes (#1)" do
    pair, = register_key
    source = create_source(pair, title: "Moonshots episode 123")
    nodes = [ { "heading" => "Moonshots episode 123", "sections" => [
      { "heading" => "LLM alignment", "sections" => [ { "heading" => "OpenAI" }, { "heading" => "Anthropic" }, { "heading" => "Open models" } ] },
      { "heading" => "Math is cooked", "sections" => [ { "heading" => "Millennium Prize" } ] } ] } ]
    created = outline(pair, source, nodes)
    expect(created.size).to eq(7)
    root = created.find(&:root?)
    expect(root.heading).to eq("Moonshots episode 123")
    expect(root.id).to eq(Ledger::Ids.derive(root.contribution_id, "section", 0))
    expect(created.map(&:root_id).uniq).to eq([ root.id ])
    openai = Section.find_by(heading: "OpenAI")
    expect(openai.depth).to eq(2)
    expect(openai.path).to eq([ "Moonshots episode 123", "LLM alignment", "OpenAI" ])
    expect(created).to all(be_accepted)

    more = outline(pair, source, [ { "heading" => "Robotics" } ], parent: root)
    expect(more.first).to have_attributes(parent_id: root.id, root_id: root.id, position: 2)

    get "/sections/#{root.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("LLM alignment").and include("Millennium Prize").and include("Robotics")
    expect(response.body).to include(Sections::Tree::NOTE)

    deep = (1..7).reduce({ "heading" => "leaf" }) { |acc, i| { "heading" => "level #{i}", "sections" => [ acc ] } }
    expect_rejected("SCHEMA_INVALID") { outline(pair, source, [ deep ]) }
    expect_rejected("SCHEMA_INVALID") { outline(pair, source, [ { "heading" => "x" * 121 } ]) }
    expect_rejected("SCHEMA_INVALID") { outline(pair, source, Array.new(501) { |i| { "heading" => "s#{i}" } }) }
    other = create_source(pair, title: "Other")
    location = create_location(pair, other)
    expect_rejected("TARGET_UNKNOWN") { outline(pair, source, [ { "heading" => "x", "location_id" => location.id } ]) }
    expect_rejected("SCHEMA_INVALID") { append(action_type: "CREATE_SECTION", key_pair: pair, payload: { "source_id" => source.id, "parent_section_id" => root.id, "sections" => [ { "heading" => "x" } ] }.merge("source_id" => other.id)) }
  end

  it "places claims at birth and by PLACE_CLAIM, shows the tree beside the claim, and removes a placement by INVALIDATE (#2)" do
    pair, = register_key
    source = create_source(pair)
    root, alignment = outline(pair, source, [ { "heading" => "Episode", "sections" => [ { "heading" => "Alignment" } ] } ])
    born = create_claim(pair, "Born in a section.", section_id: alignment.id)
    placement = ClaimPlacement.find_by(claim_id: born.id)
    expect(placement).to have_attributes(section_id: alignment.id, accepted_seq: born.accepted_seq)

    other = create_claim(pair, "Filed later.")
    result = append(action_type: "PLACE_CLAIM", key_pair: pair, payload: { "claim_id" => other.id, "section_id" => alignment.id })
    expect(ClaimPlacement.where(section_id: alignment.id).count).to eq(2)
    expect_rejected("DUPLICATE") { append(action_type: "PLACE_CLAIM", key_pair: pair, payload: { "claim_id" => other.id, "section_id" => alignment.id, "position" => 9 }) }
    second_root, = outline(pair, source, [ { "heading" => "Another outline" } ])
    append(action_type: "PLACE_CLAIM", key_pair: pair, payload: { "claim_id" => other.id, "section_id" => second_root.id })

    get "/claims/#{other.id}?section=#{alignment.id}"
    expect(response.body).to include('class="with-outline"')
    expect(response.body).to include("claim-line current")
    expect(response.body).to include("Also in:")
    expect(response.body.scan("<details open>").size).to be >= 1
    get "/api/v1/claims/#{other.id}"
    paths = response.parsed_body.dig("claim", "sections").map { |s| s["path"] }
    expect(paths).to include([ "Episode", "Alignment" ]).and include([ "Another outline" ])

    seq_before = Contribution.maximum(:seq)
    moderator_pair, = register_moderator
    append(action_type: "INVALIDATE", key_pair: moderator_pair, payload: { "contribution_id" => result.contribution.id, "reason" => "misfiled" })
    expect(Sections::Tree.placements_for(other, Contribution.maximum(:seq)).map(&:id)).to eq([ second_root.id ])
    expect(Sections::Tree.placements_for(other, seq_before).map(&:id)).to match_array([ alignment.id, second_root.id ])
  end

  it "counts by state with no probability for any section, and replays byte for byte (#3, #4)" do
    pair, = register_key
    source = create_source(pair)
    root, = outline(pair, source, [ { "heading" => "Speech" } ])
    a = create_claim(pair, "A claim with no evidence.", section_id: root.id)
    b = create_claim(pair, "We should do better.", type: "NORMATIVE", section_id: root.id)
    seq = Contribution.maximum(:seq)
    tree = Sections::Tree.call(root, seq)
    expect(tree[:counts]).to include("claims" => 2, "checkable" => 1, "INSUFFICIENT_EVIDENCE" => 1, "NOT_APPLICABLE" => 1)
    expect(Sections::Tree.counts_line(tree[:counts])).to eq("2 claims · 1 checkable · 1 insufficient evidence · 1 not applicable")
    expect(tree.keys).not_to include(:probability, :headline, :badge)

    get "/api/v1/sections/#{root.id}"
    body = response.parsed_body
    expect(body.dig("section", "counts", "claims")).to eq(2)
    expect(body.dig("section", "claims").map { |c| c["id"] }).to match_array([ a.id, b.id ])
    expect(body.to_json).not_to include("probability")
    get "/api/v1/sections"
    expect(response.parsed_body["sections"].first["id"]).to eq(root.id)

    before = Ledger::TableDigest.projections
    Ledger::Replay.call
    expect(Ledger::TableDigest.projections).to eq(before)
    expect(Ledger::Verify.call).to be_ok
  end

  it "lets a signed-in person add an outline from indented headings and file a claim (#5)" do
    post "/users", params: { user: { email_address: "me@example.com", password: password, password_confirmation: password } }
    user = User.find_by!(email_address: "me@example.com")
    pair = Crypto::Ed25519::KeyPair.generate
    register_key(pair)
    source = create_source(pair, title: "Transcript")
    claim = create_claim(pair, "Something said in the episode.")

    post "/sections", params: { source_id: source.id, outline: "Episode 123\n  LLM alignment\n    OpenAI\n  Math is cooked\n" }
    root = Section.find_by(heading: "Episode 123")
    expect(response).to redirect_to(section_path(root))
    expect(root.children.map(&:heading)).to eq([ "LLM alignment", "Math is cooked" ])
    expect(Section.find_by(heading: "OpenAI").depth).to eq(2)
    expect(Sections::Outline.parse("A\n  B\n  C\nD")).to eq([ { "heading" => "A", "sections" => [ { "heading" => "B" }, { "heading" => "C" } ] }, { "heading" => "D" } ])

    post "/claims/#{claim.id}/place", params: { section_id: Section.find_by(heading: "OpenAI").id }
    expect(ClaimPlacement.where(claim_id: claim.id).count).to eq(1)
    get "/sections"
    expect(response.body).to include("Episode 123").and include("Transcript")
    get "/"
    expect(response.body).to include(">Outlines<")
  end
end
