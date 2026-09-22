require "rails_helper"

# An agent skims and truncates; that is the medium, not a failing. On 2026-09-22
# a connected assistant cut the record_investigation result short, never reached
# the investigation URL — eighth key, nested inside `share`, behind an array of
# cards — and reported that it had not been given one.
RSpec.describe "A result leads with the thing the call was for", type: :request do
  include GraphHelpers
  before { release_models }

  def record
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                           params: { name: "record_investigation", arguments: {
                             "statement" => "A statement worth checking.",
                             "sources" => [ { "handle" => "s", "type" => "SECONDARY_TEXT", "title" => "A report",
                                              "url" => "https://example.com/r", "retrieved_at" => "2026-09-22T19:30:00Z" } ],
                             "excerpts" => [ { "handle" => "x", "source" => "s", "text" => "The report says the thing." } ],
                             "claims" => [ { "handle" => "c", "text" => "The thing is so.", "type" => "OBSERVATIONAL" } ],
                             "evidence" => [ { "handle" => "e", "excerpt" => "x", "statement" => "The report states it." } ],
                             "links" => [ { "evidence" => "e", "claim" => "c", "direction" => "SUPPORT" } ]
                           } } }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    response.parsed_body.dig("result", "structuredContent")
  end

  it "puts the link and the share line before anything else" do
    data = record

    expect(data["errors"]).to be_nil
    expect(data.keys.first(2)).to eq(%w[url share_line])
    expect(data["url"]).to include("/investigations/")
  end

  # The text block is what a model reads when it does not parse the JSON, and it
  # is truncated from the end — so the link has to be near the top of that too.
  it "puts it near the top of the text a reader actually sees" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                           params: { name: "list_topics", arguments: {} } }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }
    data = record

    text = response.parsed_body.dig("result", "content", 0, "text").to_s
    expect(text.index(data["url"])).to be < 200,
      "the link must survive a reader that stops early"
  end

  # A contract that omits what it returns is a contract a caller cannot follow.
  it "declares every key it returns" do
    data = record
    declared = Mcp::Server::RECORD_OUTPUT_SCHEMA[:properties].keys.map(&:to_s)

    undeclared = data.keys - declared - %w[guidance waiting_on_you]
    expect(undeclared).to eq([]), "record_investigation returns #{undeclared.join(', ')} without declaring it"
    expect(declared.first(2)).to eq(%w[url share_line]), "the contract should read in the order the result arrives"
  end
end
