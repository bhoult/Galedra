require "rails_helper"

# Stage 42 §8: a claim that holds most of the query's words is found even when
# it lacks one of them (bug report 91bee9ac).
RSpec.describe "search_claims when no claim holds every word", type: :request do
  before { release_models }

  let(:curator) { register_key(display_name: "Curator").first }

  def search(query)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "search_claims", arguments: { query: query } } }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body.dig("result", "structuredContent")
  end

  it "finds a claim holding most of the words, and not one holding too few" do
    # Long, as real claims are, so the similar-wording fallback does not rescue a
    # short query: it scores the whole sentence against the query and falls below
    # its threshold. That is the case the filer met.
    barred = create_claim(curator, "In a post on Truth Social on September 18, 2026, Donald Trump announced that reporters from CNN, " \
                                   "MS NOW and Politico were barred from the White House grounds, and said that other outlets would follow.", type: "HISTORICAL")
    create_claim(curator, "The White House garden was replanted in the spring.", type: "HISTORICAL")

    # "ban" and "press" are in no claim, so every-word matching finds nothing.
    expect(Claims::Duplicates.candidates("Trump ban CNN Politico press").to_a).to be_empty, "the fallback must not be what finds it"
    found = search("Trump ban CNN Politico press")
    expect(found["claims"].map { |c| c["id"] }).to eq([ barred.id ])

    # Two of six words is under half, so the garden is not offered as a hit.
    expect(search("White House cabinet reshuffle economic advisers")["claims"]).to eq([])
  end
end
