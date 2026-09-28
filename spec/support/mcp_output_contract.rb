# frozen_string_literal: true

# Every tool result any spec produces is checked against the outputSchema that
# tool publishes (Mcp::Output). In production a mismatch is a log line,
# outcome=output_invalid, because the caller's client is what refuses it; here
# it fails the example that produced it. A field that can be null under a schema
# that does not allow null reached a live assistant three times on 2026-09-28
# (bug reports 01a0e96a, 01a0e992, 01a0e99a), with every spec passing.
#
# Collected and failed after the example rather than raised in place, because
# Mcp::Server#handle rescues StandardError into a tool error on purpose, and a
# spec that never looks at the error flag would pass straight through it.
module McpOutputContract
  BROKEN = []

  def call_tool(params)
    result = super
    tool = Mcp::Server::TOOLS.find { |t| t[:name] == params["name"].to_s }
    if tool && result.is_a?(Hash) && !result[:isError]
      broken = Mcp::Output.errors(tool, JSON.parse(result[:content].first[:text]))
      BROKEN << "#{tool[:name]}: #{broken.join('; ')}" if broken.any?
    end
    result
  end
end

Mcp::Server.prepend(McpOutputContract)

RSpec.configure do |c|
  c.before { McpOutputContract::BROKEN.clear }
  c.after do
    broken = McpOutputContract::BROKEN.dup
    McpOutputContract::BROKEN.clear
    raise "a tool returned a result its own outputSchema forbids — #{broken.join(' | ')}" if broken.any?
  end
end
