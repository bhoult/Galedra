require "rails_helper"
require "skills/build"

RSpec.describe Skills::Build do
  it "keeps the generated skill files identical to the source rendering (#3)" do
    expect(described_class.stale).to eq([]), "run bin/rails skills:build; stale: #{described_class.stale.join(', ')}"
    described_class.outputs.each_value do |text|
      expect(text).to include("Search first")
      expect(text).to include("Your own reasoning is never evidence")
      expect(text).to include("GALEDRA_URL")
    end
    expect(described_class.claude).to start_with("---\nname: galedra\n")
    expect(described_class.chatgpt).to include("openapi.json")
    expect(described_class.generic).to include("/mcp")
  end
end
