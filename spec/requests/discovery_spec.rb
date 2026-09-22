require "rails_helper"

# Every rule this node has for a connected assistant assumed the agent had
# already found /mcp. A probe on 2026-09-22 found nothing at any path an agent
# tries unprompted, and no machine-readable pointer in the HTML Muse had just
# fetched before it went looking in a browser.
RSpec.describe "What an agent finds when it is handed only the address", type: :request do
  it "serves llms.txt as plain text" do
    get "/llms.txt"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/plain")
  end

  it "answers with this node's own address rather than one written down here" do
    allow(Ledger::Node).to receive(:url).and_return("https://somewhere-else.example")
    get "/llms.txt"

    expect(response.body).to include("https://somewhere-else.example/mcp")
    expect(response.body).not_to include("local.galedra.org")
  end

  # A pointer that points at a 404 is worse than no pointer: it sends an agent
  # somewhere and it is not there. Same rule as the refusals.
  it "names only paths this node actually serves" do
    get "/llms.txt"
    # The token form is written with a placeholder, so give it one that looks
    # like a token rather than dropping the only route a connector form can use.
    body = response.body.gsub("gal_<token>", "gal_ExampleTokenValue")
    paths = body.scan(%r{#{Regexp.escape(Ledger::Node.url)}(/[\w./-]*)}).flatten.uniq

    expect(paths).to include("/mcp", "/api/v1/guidance", "/api/v1/openapi")
    paths.each do |path|
      expect { Rails.application.routes.recognize_path(path) }
        .not_to raise_error, "llms.txt points at #{path}, which is not routed"
    end
  end

  it "carries the rule an agent has to know before its first call" do
    get "/llms.txt"

    expect(response.body).to include("never by fetching")
    expect(response.body).to include("list_tasks"), "a standing queue nobody mentions is a queue nobody works"
    expect(response.body).to include("open_for_you")
    expect(response.body).to include(Guidance::VERSION)
  end

  # The reason this file is short. `Guidance` is served live on every result so
  # that a correction reaches a live session; a copy of it here would be frozen
  # at whatever it said the day someone read it, which is the failure Stage 31
  # exists to avoid.
  it "points at the rules instead of copying them" do
    get "/llms.txt"

    expect(response.body).to include("/api/v1/guidance")
    Guidance::TOPICS.each do |topic|
      expect(response.body).not_to include(Guidance.for(topic).to_s[0, 120]),
                                  "llms.txt has begun copying the #{topic} guidance; it must point at it"
    end
  end

  it "points at the tools from the page an agent actually fetched" do
    get "/"

    expect(response.body).to include('href="/llms.txt"')
    expect(response.body).to include('href="/api/v1/openapi"')
    expect(response.body).to include('href="/api/v1/guidance"')
  end
end
