require "rails_helper"

RSpec.describe "Paste an investigation (after Stage 14)", type: :request do
  before { release_models }

  def bundle
    JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about").tap do |b|
      b["sources"].each { |s| s["retrieved_at"] = Time.now.utc.iso8601 }
    end
  end

  it "records a pasted bundle under a session-scoped anonymous assistant and shows the cards" do
    get "/investigations/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Brackenridge")

    post "/investigations", params: { bundle: bundle.to_json }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Recorded")
    expect(response.body).to include("The evidence leans against this.")
    expect(response.body).to include("Say instead:")
    token = AssistantToken.last
    expect(token.software["agent_name"]).to eq("Pasted by hand")
    expect(token.principal).to be_anonymous

    post "/investigations", params: { bundle: bundle.merge("claims" => [ { "handle" => "x", "text" => "A second paste in the same session.", "type" => "TEXTUAL" } ], "links" => [], "evidence" => [], "excerpts" => [], "sources" => []).to_json }
    expect(response).to have_http_status(:ok)
    expect(AssistantToken.count).to eq(1)
  end

  it "shows similar claims and attaches on request, and reports invalid bundles without appending" do
    curator, = register_key(display_name: "Curator")
    existing = create_claim(curator, "Brackenridge has banned bicycles downtown.")
    epistemic = -> { Contribution.where.not(action_type: %w[REGISTER_KEY DELEGATE]).count }
    count = epistemic.call

    post "/investigations", params: { bundle: bundle.to_json }
    expect(response.body).to include("Similar claims already exist")
    expect(response.body).to include(existing.id)
    # Only the session's assistant key and delegation were minted; nothing epistemic.
    expect(epistemic.call).to eq(count)

    post "/investigations", params: { bundle: bundle.to_json, on_duplicate: "create", attach: { "ban" => existing.id, "narrow" => "" } }
    expect(response.body).to include("attached to an existing claim")
    expect(EvidenceClaimLink.where(claim_id: existing.id).count).to be > 0

    post "/investigations", params: { bundle: "{nope" }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("not valid JSON")

    bad = bundle
    bad["links"][0]["direction"] = "MAYBE"
    before = Contribution.count
    post "/investigations", params: { bundle: bad.to_json }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("$.links[0].direction")
    expect(Contribution.count).to eq(before)
  end
end
