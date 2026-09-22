require "rails_helper"

# The README carries the agent instructions in full, so a contributor reading
# GitHub does not have to visit the site. That is a second copy of something the
# site also serves, and a second copy is the one that goes stale — so the part
# that can rot is held to the live registry.
RSpec.describe "The README's agent instructions", type: :request do
  let(:readme) { File.read(Rails.root.join("README.md")) }
  let(:section) { readme[/### Contributing with an AI agent.*?\n(?=^## )/m] || readme[/### Contributing with an AI agent.*/m] }

  it "is there" do
    expect(section).to be_present
  end

  # Every tool it tells an agent to call has to exist, or the instructions send
  # somebody to a refusal on their first attempt.
  it "names only tools this node serves" do
    named = section.scan(/`([a-z]+(?:_[a-z]+)+)`/).flatten.uniq
    tools = Mcp::Server::TOOLS.map { |t| t[:name] }
    not_tools = %w[Authorization introduce_yourself]

    expect(named).to include("search_claims", "record_investigation", "share_card", "introduce_yourself")
    unknown = named - tools - not_tools
    expect(unknown).to eq([]), "README names #{unknown.join(', ')}, which are not tools"
  end

  it "would catch an instruction naming a tool that does not exist" do
    named = "call `delete_everything` first".scan(/`([a-z]+(?:_[a-z]+)+)`/).flatten
    expect(named - Mcp::Server::TOOLS.map { |t| t[:name] }).to eq([ "delete_everything" ])
  end

  # The corrections that were made to this text before it was published, which a
  # later paste of the original would quietly undo.
  it "keeps the corrections" do
    expect(section).to include("introduce_yourself"), "nobody has to hand an agent a credential"
    expect(section).not_to match(/ask me for the credential/i)
    expect(section).to include("identifiable private individual"), "the workflow reads somebody's feed"
    expect(section).to include("wait for my approval")
    expect(section).to include("works for Meta's own agent and for nobody else").or include("for nobody else")
  end

  # The person is paying for the agent out of an allowance they also want for
  # their own work, and nothing anywhere said so: Guidance's "stop when your cap
  # is near" means Galedra's hourly cap, not their subscription.
  it "tells the agent not to spend the whole allowance" do
    expect(section).to include("Do not spend everything I have")
    expect(section).to include("60%"), "Muse's free tier is generous enough to spend more of"
    expect(section).to include("no more\n>    than about a quarter").or include("about a quarter")
    expect(section).to include("where you are when you stop")
  end

  it "points at the page that carries the live endpoint" do
    expect(section).to include("/contribute")
  end

  # A path it names has to be one this node routes.
  it "names a real investigation path" do
    expect(section).to include("/investigations/")
    expect(Rails.application.routes.recognize_path("/investigations/01a00000-0000-7000-8000-000000000000"))
      .to include(controller: "investigations", action: "show")
  end
end
