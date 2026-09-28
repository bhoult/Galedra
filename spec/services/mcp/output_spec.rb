require "rails_helper"

# A result that breaks its own outputSchema is refused by the caller's client,
# so this node logged outcome=ok three times on 2026-09-28 for calls that had
# failed (bug reports 01a0e96a, 01a0e992, 01a0e99a). spec/support/
# mcp_output_contract.rb holds every spec's tool results to their schemas; this
# holds the check itself.
RSpec.describe Mcp::Output do
  it "compiles every published output schema" do
    Mcp::Server::TOOLS.each do |tool|
      next unless tool[:outputSchema]

      expect(JSONSchemer.valid_schema?(JSON.parse(tool[:outputSchema].to_json))).to be(true), "#{tool[:name]}'s outputSchema is not valid JSON Schema"
    end
  end

  it "names what a result breaks, as the caller's validator would" do
    tool = { name: "example_tool", outputSchema: { type: "object", properties: { proposal: { type: "object" } } } }

    expect(described_class.errors(tool, { "proposal" => nil })).to eq([ "/proposal (object)" ])
    expect(described_class.errors(tool, { "proposal" => { "slug" => "democrat" } })).to eq([])
  end

  it "logs a broken result as output_invalid rather than ok" do
    server = Mcp::Server.new(token: nil, base_url: "http://www.example.com")
    allow(server).to receive(:tool_list_topics).and_return({ topics: "not a list" })
    lines = []
    allow(Rails.logger).to receive(:info).and_wrap_original { |m, msg = nil, &b| lines << msg.to_s; m.call(msg, &b) }

    server.call_tool("name" => "list_topics", "arguments" => {})
    McpOutputContract::BROKEN.clear # deliberate here; the contract would otherwise fail this example

    line = lines.find { |l| l.start_with?("mcp_call tool=list_topics") }
    expect(line).to include("outcome=output_invalid", "/topics")
  end
end
