require "rails_helper"

# The completeness gauge shows wherever a score shows, and a score line prints
# its figure once (owner, 2026-09-29: "Score: 0.7758 · 0.7758 under …" had it
# twice).
RSpec.describe "Completeness gauge beside every score", type: :request do
  before { release_models }

  let(:pair) { register_key.first }
  let(:token) { AssistantToken.find_by_token(Assistants::Connect.call(name: "Checker", provider: "other").last) }

  it "appears on every page that shows a score" do
    source = create_source(pair, title: "Council minutes", content: "The council voted to close the harbour for dredging in May.")
    claim = create_claim(pair, "The harbour closed for dredging in May.", type: "OBSERVATIONAL")
    link_evidence(pair, create_evidence(pair, create_location(pair, source), statement: "The minutes record the closure vote."), claim)
    Investigation.create!(id: SecureRandom.uuid_v7, assistant_token: token, statement: "Was the harbour closed in May?", claim_ids: [ claim.id ], snapshot_seq: Contribution.maximum(:seq))
    # The outline is of another source: evidence from the source a claim was
    # taken out of weighs nothing, and there would be no score to put a gauge by.
    transcript = create_source(pair, title: "Meeting recording", content: "A transcript of the council meeting.")
    outline = append(action_type: "CREATE_SECTION", key_pair: pair, payload: { "source_id" => transcript.id, "sections" => [ { "heading" => "Council meeting" } ] })
    root = Section.find(Ledger::Ids.derive(outline.contribution.id, "section", 0))
    append(action_type: "PLACE_CLAIM", key_pair: pair, payload: { "claim_id" => claim.id, "section_id" => root.id })

    { "claim page" => claim_path(claim), "share card" => card_claim_path(claim), "source page" => source_path(source),
      "claims list" => claims_path, "investigation" => investigation_path(Investigation.last),
      "investigations list" => investigations_path, "outline" => section_path(root), "outlines list" => sections_path }.each do |page, path|
      get path
      expect(response).to have_http_status(:ok), "#{page} answered #{response.status}"
      # The rule itself: a page showing a score shows the gauge. A source page
      # lists only claims extracted from it, which this fixture has none of.
      next if page == "source page" && !response.body.include?("score-line")

      expect(response.body).to match(/class="meter[ "]|class="meter-bar /), "#{page} shows a score and no completeness gauge"
    end

    get investigations_path
    lines = response.body.scan(%r{<p class="meta score-line"[^>]*>(.*?)</p>}m).flatten.map { |l| l.gsub(/<[^>]+>/, "") }
    expect(lines).not_to be_empty
    lines.each { |line| expect(line).not_to match(/\AScore: ([0-9.]+) ·? ?\1/), "the figure is printed once: #{line}" }
  end
end
