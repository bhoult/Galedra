require "rails_helper"

# A session ends and the next one begins knowing nothing. On 2026-09-22 one
# ChatGPT session filed a bug report and a later session from the same account
# had no idea it existed, so it could not read the answer or say whether it
# settled anything. The node was never in doubt about who it was talking to —
# every call carries a token, and a named token follows its principal — so what
# was missing is that nobody told it.
RSpec.describe "Telling a connection what it left hanging", type: :request do
  include GraphHelpers

  let(:user) { User.create!(email_address: "filer@example.com", password: "correct horse battery staple") }
  let(:plaintext) { Assistants::Connect.call(user: user, name: "Claude", provider: "anthropic").last }
  let(:token) { AssistantToken.find_by_token(plaintext) }
  let(:maintainer) { User.create!(email_address: "admin@example.com", password: "correct horse battery staple", admin: true) }

  def result(name = "list_topics", arguments = {})
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                           params: { name: name, arguments: arguments } }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{plaintext}" }
    response.parsed_body.dig("result", "structuredContent")
  end

  it "says nothing when there is nothing to say" do
    expect(result).not_to have_key("waiting_on_you")
  end

  it "names the reports answered and waiting on the filer, wherever the answer was given" do
    report = BugReport.record!(happened: "A page did something odd", expected: "it not to", token: token).first
    # Filed and not yet answered: a count, so a later session does not refile it.
    waiting = result["waiting_on_you"]
    expect(waiting["open"]).to eq(1)
    expect(waiting["answered"]).to be_empty
    expect(waiting["note"]).to include("Do not file the same thing twice")

    report.answer!(body: "Fixed in a4b1c2d; does that settle it?", user: maintainer)
    waiting = result["waiting_on_you"]
    expect(waiting["answered"]).to eq([ report.id ])
    expect(waiting["open"]).to be_zero
    expect(waiting["note"]).to include("respond_to_report")
    expect(waiting["note"]).to include("closes itself")
  end

  # Held is a different obligation: work was agreed and is not done, so nothing
  # is wanted from the filer. It is said so a later session can see where it
  # stands instead of filing it again.
  it "separates work a maintainer agreed to do from an answer that wants a reply" do
    report = FeatureRequest.record!(token: token, asked: "Work the open tasks",
                                    needed: "A way to cite an excerpt I just recorded",
                                    expected: "submit_task to take a source_location_id").first
    report.answer!(body: "Agreed, and it needs a stage.", user: maintainer, settles: false)

    waiting = result["waiting_on_you"]
    expect(waiting["held"]).to eq([ report.id ])
    expect(waiting["answered"]).to be_empty
    expect(waiting["note"]).to include("a maintainer agreed to work that is not done yet")
    expect(waiting["note"]).to include("you need not file it again")
  end

  # The whole point: a new connection, which is what a new session gets.
  it "follows the principal, so a later connection finds what an earlier one filed" do
    report = BugReport.record!(happened: "Something from the first session", expected: "otherwise", token: token).first
    report.answer!(body: "Answered.", user: maintainer)

    later = Assistants::Connect.call(user: user, name: "Claude again", provider: "anthropic").last
    post "/mcp", params: { jsonrpc: "2.0", id: 2, method: "tools/call",
                           params: { name: "list_topics", arguments: {} } }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{later}" }

    expect(response.parsed_body.dig("result", "structuredContent", "waiting_on_you", "answered")).to eq([ report.id ])
  end

  it "never shows one filer another's reports" do
    mine = BugReport.record!(happened: "Mine", expected: "otherwise", token: token).first
    other_user = User.create!(email_address: "other@example.com", password: "correct horse battery staple")
    other = AssistantToken.find_by_token(Assistants::Connect.call(user: other_user, name: "Someone else", provider: "other").last)
    theirs = BugReport.record!(happened: "Theirs", expected: "otherwise", token: other).first
    [ mine, theirs ].each { |r| r.answer!(body: "Answered.", user: maintainer) }

    expect(result["waiting_on_you"]["answered"]).to eq([ mine.id ])
  end
end
