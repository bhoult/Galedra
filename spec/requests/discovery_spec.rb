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
  # The pointers in <head> are belt and braces. On 2026-09-22 this page was
  # fetched the way an agent fetches it and the reply was explicit: no <link
  # rel> tags, no HTML comments, only the rendered prose. Whatever an agent is
  # told here has to survive a markdown conversion, which means visible text.
  describe "an agent that was handed the URL and fetched the page" do
    it "is told in visible text to call tools, and given the endpoint" do
      get "/"
      text = response.body.gsub(/<script.*?<\/script>|<style.*?<\/style>/m, "").gsub(/<!--.*?-->/m, "")
                          .gsub(/<[^>]+>/, " ").gsub(/\s+/, " ")

      expect(text).to include("If you are an AI assistant, read this first")
      expect(text).to include("never by fetching the page")
      expect(text).to include("#{Ledger::Node.url}/mcp")
      expect(text).to include("llms.txt")
      expect(text).to include("list_tasks")
    end

    # Collapsed for a person, whole in the document for an agent. The guard is
    # that it must never become display:none — that reaches agents just as well
    # and is cloaking, which is the thing this project argues against.
    it "is collapsed rather than hidden" do
      get "/"

      expect(response.body).to include('<details class="agent-note">')
      css = File.read(Rails.root.join("app/assets/stylesheets/application.css"))
      rule = css[/\.agent-note[^{]*\{[^}]*\}/]
      expect(rule).not_to include("display: none"), "an instruction block a person cannot see is cloaking"
      expect(css).not_to match(/\.agent-note[^{]*\{[^}]*visibility:\s*hidden/)
    end

    # Near the top, because what reaches an agent's reasoning is whatever
    # survives someone else's summary of the page.
    it "says it early enough to survive a summary" do
      get "/"
      text = response.body.gsub(/<script.*?<\/script>|<style.*?<\/style>/m, "").gsub(/<[^>]+>/, " ").gsub(/\s+/, " ")

      expect(text.index("If you are an AI assistant")).to be < (text.length * 0.08),
        "the agent notice has drifted down the page; a summary will drop it"
    end
  end

  # The page between "give your assistant one address", which never named the
  # address, and /assistants/new, which mints a token for somebody who already
  # knows what to do with one.
  describe "how a person connects their assistant" do
    it "names the address, in this node's own terms" do
      allow(Ledger::Node).to receive(:url).and_return("https://somewhere-else.example")
      get "/connect"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("https://somewhere-else.example/mcp")
      expect(response.body).not_to include("local.galedra.org")
    end

    it "covers all three ways a client may ask for the credential" do
      get "/connect"

      expect(response.body).to include("Authorization: Bearer")
      expect(response.body).to include("/mcp/gal_"), "the URL form is the one a connector screen with no headers needs"
      expect(response.body).to include("/mcp/connect")
    end

    # The only channel this node cannot speak on for itself: a directory-style
    # client decides a connector is relevant from the operator's description,
    # before it ever reads a tool list.
    it "hands the operator the words for a connector directory" do
      get "/connect"

      expect(response.body).to include("never by opening a browser")
      expect(response.body).to include("list_tasks")
      expect(response.body).to include("open_for_you")
    end

    it "is reachable from the landing page" do
      get "/"
      expect(response.body).to include('href="/connect"')
    end
  end
end
