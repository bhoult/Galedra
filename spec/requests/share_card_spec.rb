require "rails_helper"

RSpec.describe "Share card (Stage 14)", type: :request do
  before { release_models }

  it "carries Open Graph tags and renders an image for a claim in each assessment state, with the number only in its stated form (#4)" do
    graph = build_public_demo
    model = Scoring::Registry.default_model
    seq = Contribution.maximum(:seq)
    states = {}
    graph.claims.each_value do |claim|
      next if Governance::Quarantines.live_for("CLAIM", claim.id)

      states[Scoring::Score.call(claim, seq, model).assessment_state] ||= claim
    end
    curator, = register_key(display_name: "Curator")
    states["INSUFFICIENT_EVIDENCE"] ||= create_claim(curator, "Nothing bears on this.")
    expect(states.keys).to include("UNRESOLVED", "LEANS_CONTRADICTED", "NOT_APPLICABLE", "INSUFFICIENT_EVIDENCE")

    states.each do |state, claim|
      get "/claims/#{claim.id}/card"
      expect(response).to have_http_status(:ok), state
      expect(response.body).to include('property="og:title"')
      expect(response.body).to include("/claims/#{claim.id}/card.png")
      expect(response.body).to include('name="twitter:card" content="summary_large_image"')
      # The number appears only in its stated form, with model and snapshot, never as a percentage or in the headline (06 §4).
      expect(response.body[%r{<p class="meta">.*?</p>}m]).not_to match(/\d+%/)
      expect(response.body.scan(/\b0\.\d{4}\b/).size).to eq(response.body.scan(/\b0\.\d{4} under #{Regexp.escape(Scoring::Registry.default_model.full_name)} at snapshot \d+/).size)
      expect(response.body).not_to match(/og:title" content="[^"]*0\.\d{4}/)

      get "/claims/#{claim.id}/card.png"
      expect(response).to have_http_status(:ok), state
      expect(response.media_type).to eq("image/png")
      expect(response.body[0, 4]).to eq("\x89PNG".b)
      expect(response.body.bytesize).to be > 5_000
    end

    c2 = graph.claims["C2"]
    get "/claims/#{c2.id}/card"
    expect(response.body).to include("Say instead:")
    expect(response.body).to include(graph.claims["C3"].canonical_text)
  end
end
