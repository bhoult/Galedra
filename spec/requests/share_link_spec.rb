require "rails_helper"

RSpec.describe "The link to paste (after Stage 19)", type: :request do
  before { release_models }

  let(:token) { Assistants::Connect.call(name: "Claude", provider: "anthropic").last }

  def call_tool(name, arguments)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }
    [ response.parsed_body.dig("result", "structuredContent"), response.parsed_body.dig("result", "isError") ]
  end

  def bundle
    JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about").tap do |b|
      b["sources"].each { |s| s["retrieved_at"] = Time.now.utc.iso8601 }
      b["statement"] = "Brackenridge just BANNED bicycles downtown!! Share before they delete this."
    end
  end

  it "records what was asked, answers with a share line, and serves the page, its preview tags, and a PNG" do
    data, err = call_tool("record_investigation", bundle)
    expect(err).to be(false), data.inspect
    share = data["share"]
    expect(share["url"]).to match(%r{http://www.example.com/investigations/[0-9a-f-]{36}})
    verdict = share["verdict"]
    expect(verdict).to include("headline" => "Parts of this go against the evidence.", "sentence" => "1 of 2 checkable claims goes against the evidence; 1 holds up so far")
    expect(verdict["stated"]).to match(/\A0\.\d{4} under #{Regexp.escape(Scoring::Registry.default_model.full_name)} at snapshot \d+ for all claims together\z/)
    expect(data["share_line"]).to eq("Checked in Galedra: Parts of this go against the evidence. (1 of 2 checkable claims goes against the evidence; 1 holds up so far) #{verdict['stated']}. #{share['url']}")
    expect(share["note"]).to include("End your reply")

    get share["url"]
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Brackenridge just BANNED bicycles").and include("og:image").and include("Say instead:").and include("Sources read")
    expect(response.body).to include("Parts of this go against the evidence.").and include("Claim by claim").and include("for all claims together")
    expect(response.body.scan(/<svg class="badge-mark"/).size).to eq(3)
    expect(verdict["badge"]).to eq("mostly_against")
    expect(response.body).to include("Leans against").or include("Mostly against")
    expect(response.body.index("badge-mark")).to be < response.body.index("Brackenridge has banned")
    expect(response.body.scan("The evidence leans against this.").size).to be <= 1
    expect(response.body).to include("Acme").or include("Council")

    get "#{share['url']}/card.png"
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.body.bytesize).to be > 5_000

    # An existing claim carries its own share line.
    ban = data["claims"].find { |c| c["handle"] == "ban" }
    data, = call_tool("get_claim", { claim_id: ban["id"] })
    expect(data["share_line"]).to eq("Checked in Galedra: #{data.dig('card', 'plain', 'headline')} #{data.dig('card', 'stated')}. #{ban['url']}/card")
    expect(data.dig("card", "stated")).to match(/\A0\.\d{4} under #{Regexp.escape(Scoring::Registry.default_model.full_name)} at snapshot \d+\z/)
    data, = call_tool("search_claims", { query: "Brackenridge bicycles" })
    expect(data["claims"].first["share_line"]).to start_with("Checked in Galedra: ")
    data, = call_tool("fetch", { id: ban["id"] })
    expect(data["text"]).to include("Share: Checked in Galedra:")
  end

  it "works without a statement, gives one headline when one claim answers, and rejects an oversized statement" do
    data, err = call_tool("record_investigation", { "claims" => [ { "handle" => "c", "text" => "A single unsourced claim about kites.", "type" => "OBSERVATIONAL" } ] })
    expect(err).to be(false), data.inspect
    expect(data["share_line"]).to eq("Checked in Galedra: Nobody has checked this yet. #{data['share']['url']}")
    expect(data["claims"].first.dig("card", "stated")).to be_nil
    get data["share"]["url"]
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("A single unsourced claim about kites.")

    # An existing claim by reference plus an opinion: the page covers the whole statement.
    kites = data["claims"].first["id"]
    data, err = call_tool("record_investigation", { "statement" => "Kites are amazing and schools should teach kite-making instead of algebra.",
                                                    "claims" => [ { "handle" => "k", "attach_to" => kites }, { "handle" => "n", "text" => "Schools should teach kite-making instead of algebra.", "type" => "NORMATIVE" } ] })
    expect(err).to be(false), data.inspect
    expect(data["share"]["verdict"]).to include("headline" => "Not settled yet.", "sentence" => "1 not yet settled; 1 not a checkable fact", "stated" => nil, "badge" => "not_checked")
    expect(data["share_line"]).to eq("Checked in Galedra: Not settled yet. (1 not yet settled; 1 not a checkable fact) #{data['share']['url']}")
    get data["share"]["url"]
    expect(response.body).to include("A single unsourced claim about kites.").and include("Not a checkable fact")

    data, err = call_tool("record_investigation", { "statement" => "x" * 2_001, "claims" => [ { "handle" => "c", "text" => "Another claim about kites.", "type" => "OBSERVATIONAL" } ] })
    expect(err).to be(true)
    expect(data["errors"].first["path"]).to eq("$.statement")
    expect(Investigation.count).to eq(2)
  end

  it "maps every state to one of ten badges, from green through amber to red, never in true-or-false words" do
    expect(Cards::Badge::LEVELS.size).to eq(10)
    expect(Cards::Badge.level_for("SUPPORTED", "0.9500")).to eq(:strongly_supported)
    expect(Cards::Badge.level_for("SUPPORTED", "0.8600")).to eq(:mostly_supported)
    expect(Cards::Badge.level_for("LEANS_SUPPORTED", "0.7000")).to eq(:leans_supported)
    expect(Cards::Badge.level_for("UNRESOLVED", "0.5000")).to eq(:mixed)
    expect(Cards::Badge.level_for("LEANS_CONTRADICTED", "0.3000")).to eq(:leans_against)
    expect(Cards::Badge.level_for("CONTRADICTED", "0.1500")).to eq(:mostly_against)
    expect(Cards::Badge.level_for("CONTRADICTED", "0.0500")).to eq(:strongly_against)
    expect(Cards::Badge.level_for("INSUFFICIENT_EVIDENCE", nil)).to eq(:not_checked)
    expect(Cards::Badge.level_for("NOT_APPLICABLE", nil)).to eq(:not_checkable)
    expect(Cards::Badge.level_for("QUARANTINED", nil)).to eq(:withheld)
    labels = Cards::Badge::LEVELS.values.map { |b| b[:label].downcase }
    expect(labels.grep(/\btrue\b|\bfalse\b|debunked|confirmed/)).to be_empty
    Cards::Badge::LEVELS.each_key { |k| expect(Cards::Badge.svg(k)).to start_with("<svg").and include("<circle") }
  end
end
