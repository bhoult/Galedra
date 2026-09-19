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

  # The size rule lived in three places and they disagreed: the skill and
  # create_outline both offered "over 3,000 words OR over 25 claims", and
  # record_investigation carried no ceiling at all. A connector reads the tool
  # schemas, not the skill, so an assistant holding a two-hour transcript could
  # find thirteen headline claims, satisfy the claim limb, and record them as
  # the whole check. The count of claims is the assistant's own output, so it
  # can never gate the decision; only the input size can.
  it "states one size rule, on the input, everywhere an assistant can read it (#3)" do
    surfaces = {
      "guidance(:check)" => Guidance.for(:check),
      "guidance(:outline)" => Guidance.for(:outline),
      "record_investigation" => Mcp::Server::TOOLS.find { |t| t[:name] == "record_investigation" }[:description],
      "create_outline" => Mcp::Server::TOOLS.find { |t| t[:name] == "create_outline" }[:description]
    }
    surfaces.each do |where, text|
      expect(text).to include("3,000 words"), "#{where} does not state the threshold"
      unless where == "create_outline"
        expect(text).to match(/create_outline/), "#{where} does not name the tool to use above the threshold"
      end
      expect(text).not_to match(/or (over|under) about \d+ claims/),
        "#{where} offers a claim count as an alternative to the input size; the claim count is the assistant's own output"
    end
  end

  # Stage 31. A skill is installed once and never re-read, so an operational
  # rule written into it is frozen until every user reinstalls. The rules belong
  # in Guidance, which rides on every tool result and is served at
  # /api/v1/guidance. This fails if one migrates back into the skill.
  it "keeps operational rules out of the skill and points at the live guidance (#3)" do
    source = Skills::Build.source
    expect(source).to include("api/v1/guidance")
    expect(source).to match(/guidance/i)
    Guidance::TOPICS.each { |t| expect(source).to include(t.to_s) }

    # Details that must be current at the moment of use, so they may only live
    # on the wire. Each is present in Guidance and must be absent from the skill.
    %w[3,000 TRANSCRIPTION attach_to NORMATIVE say_instead next_content_review].each do |marker|
      expect(Guidance.all.values.join(" ")).to include(marker), "#{marker} is not in the guidance at all"
      expect(source).not_to include(marker),
        "#{marker} is an operational rule in the skill; it belongs in Guidance, which is re-read on every call"
    end
  end
end
