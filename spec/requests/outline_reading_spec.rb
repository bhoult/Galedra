require "rails_helper"

RSpec.describe "An assistant records a leaf's text through the connector (Stage 30)", type: :request do
  before { release_models }

  let(:token) { Assistants::Connect.call(name: "Claude", provider: "anthropic").last }

  def call_tool(name, arguments)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }
    [ response.parsed_body.dig("result", "structuredContent"), response.parsed_body.dig("result", "isError") ]
  end

  it "offers a reading on the tool and records it, keeping the anchor as the quotation" do
    # The field has to be on the tool, or an assistant has nowhere to put the
    # text however well the skill describes it.
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }
    outline_tool = response.parsed_body.dig("result", "tools").find { |t| t["name"] == "create_outline" }
    leaf = outline_tool.dig("inputSchema", "properties", "sections", "items", "properties")
    expect(leaf).to have_key("reading")
    expect(leaf.dig("reading", "description")).to include("paragraphs")

    reading = "Remote work raises productivity, the host said.\n\nHe cited a survey of four hundred people."
    data, err = call_tool("create_outline", {
      statement: "An episode. https://example.org/ep",
      source: { type: "VIDEO", title: "An episode", url: "https://example.org/ep", retrieved_at: Time.now.utc.iso8601 },
      sections: [ { handle: "root", heading: "The episode", sections: [
        { handle: "leaf", heading: "On remote work",
          locator: { type: "TIME_RANGE", start: "00:00:00", end: "00:04:00" },
          anchor: "Remote work raises productivity, the host said.",
          reading: reading } ] } ]
    })
    expect(err).to be(false), data.inspect

    section = Section.find(data["sections"]["leaf"]["id"])
    expect(section.reading_location&.excerpt).to eq(reading)
    expect(section.reading_location.locator_type).to eq("TRANSCRIPTION")
    # The anchor is untouched and still the quotation that gets checked.
    expect(section.location.excerpt).to eq("Remote work raises productivity, the host said.")
    expect(section.location.locator_type).to eq("TIME_RANGE")

    # And the page shows the text, not just the anchor.
    get "/sections/#{section.id}"
    expect(response.body).to include("He cited a survey of four hundred people")
  end
end
