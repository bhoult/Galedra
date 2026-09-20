require "rails_helper"

RSpec.describe "Bug reports from assistants and people", type: :request do
  before { release_models }

  let(:password) { "correct horse battery staple" }
  let(:user) { User.create!(email_address: "me@example.com", password: password) }
  let(:token) { Assistants::Connect.call(user: user, name: "Claude", provider: "anthropic").last }

  def call_tool(name, arguments, tok = token)
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["Authorization"] = "Bearer #{tok}" if tok
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json, headers: headers
    body = response.parsed_body
    [ body.dig("result", "structuredContent"), body.dig("result", "isError") ]
  end

  # Filing was write-only: an assistant filed a wrong diagnosis, corrected it a
  # call later, and could neither link the two nor learn that either had been
  # read (docs/experiments/2026-09-20-second-connector-run.md).
  it "reads back what this assistant filed, with the maintainer's answer" do
    call_tool("report_bug", { happened: "add_evidence returned a malformed result", expected: "a readable error", context_tool: "add_evidence" })
    call_tool("request_feature", { asked: "work the open tasks", needed: "a way to split a mixed claim", expected: "a fork operation" })
    BugReport.last.update!(status: "ANSWERED", resolution: "Fixed: the refusal was schema-invalid, not the record.")

    data, err = call_tool("list_reports", {})
    expect(err).to be(false), data.inspect
    expect(data["total"]).to eq(2)
    bug = data["reports"].find { |r| r["kind"] == "bug" }
    expect(bug).to include("status" => "ANSWERED", "resolution" => "Fixed: the refusal was schema-invalid, not the record.")
    expect(bug["summary"]).to include("malformed result")
    expect(data["reports"].map { |r| r["kind"] }).to include("feature")

    open_only, = call_tool("list_reports", { "status" => "OPEN" })
    expect(open_only["reports"].map { |r| r["kind"] }).to eq([ "feature" ]), "the answered one is filtered out"

    # Someone else's reports are not this assistant's to read.
    other = Assistants::Connect.call(user: User.create!(email_address: "other@example.com", password: password), name: "Other", provider: "anthropic").last
    mine, = call_tool("list_reports", {}, other)
    expect(mine["total"]).to eq(0)
  end

  # A report is a conversation and is closed when both sides say so, not when one
  # side says so (owner request, 2026-09-20).
  it "runs a report back and forth until both sides agree it is closed, and shows every turn" do
    call_tool("report_bug", { happened: "add_evidence returned a malformed result", expected: "a readable error", context_tool: "add_evidence" })
    report = BugReport.last

    # A maintainer answers. That is a turn, and it hands the report back.
    report.answer!(body: "Not reproducible here.", user: user)
    expect(report.reload.status).to eq("ANSWERED")

    data, err = call_tool("list_reports", {})
    expect(err).to be(false), data.inspect
    expect(data["awaiting_you"]).to eq(1)
    expect(data["reports"].first).to include("awaiting_you" => true, "status" => "ANSWERED")

    thread, = call_tool("get_report", { "report_id" => report.id })
    expect(thread["messages"].map { |m| m["from"] }).to eq([ "maintainer" ])

    # The reporter disagrees: reopened, with the reason kept.
    back, = call_tool("respond_to_report", { "report_id" => report.id, "body" => "It reproduces on every modern client; the frame has no resultType.", "satisfied" => false })
    expect(back["status"]).to eq("OPEN")
    expect(report.reload.status).to eq("OPEN")

    # Second round, and this time the reporter agrees.
    report.answer!(body: "Found it: tool_error skipped decorate. Fixed.", user: user)
    done, = call_tool("respond_to_report", { "report_id" => report.id, "body" => "Confirmed against the live node.", "satisfied" => true })
    expect(done["status"]).to eq("CLOSED")

    thread, = call_tool("get_report", { "report_id" => report.id })
    expect(thread["messages"].map { |m| m["from"] }).to eq(%w[maintainer assistant maintainer assistant])
    expect(thread["messages"].map { |m| m["satisfied"] }).to eq([ nil, false, nil, true ])
    expect(thread["awaiting_you"]).to be(false)

    # And every turn is on the page.
    user.update!(moderator: true)
    post session_path, params: { email_address: user.email_address, password: password }
    get "/bug_reports/#{report.id}"
    expect(response.body).to include("Exchange", "Confirmed against the live node.", "not satisfied", "Closed by agreement")

    # Someone else's report is not this assistant's to read or answer.
    other = Assistants::Connect.call(user: User.create!(email_address: "other@example.com", password: password), name: "Other", provider: "anthropic").last
    _, err = call_tool("get_report", { "report_id" => report.id }, other)
    expect(err).to be(true)
  end

  it "records a report from an assistant, counts repeats, caps the day, and is named in the guidance" do
    data, err = call_tool("report_bug", { happened: "get_claim returned a card with no headline", expected: "a headline", steps: "get_claim on any claim", context_tool: "get_claim", last_error: "none" })
    expect(err).to be(false), data.inspect
    expect(data).to include("recorded" => true, "repeat" => false)
    expect(data["note"]).to include("reported")
    data, = call_tool("report_bug", { happened: "GET_CLAIM returned a card with NO headline!" })
    expect(data["repeat"]).to be(true)
    expect(BugReport.count).to eq(1)
    expect(BugReport.first).to have_attributes(count: 2, anonymous: false, context_tool: "get_claim", steps: "get_claim on any claim")
    expect(BugReport.first.reporter).to eq("Claude")

    9.times { |i| call_tool("report_bug", { happened: "bug #{i}" }) }
    data, err = call_tool("report_bug", { happened: "one too many" })
    expect(err).to be(true)
    expect(data["errors"].first["code"]).to eq("RATE_LIMITED")

    data, = call_tool("search_claims", { query: "anything" })
    expect(data.dig("guidance", "text")).to include("report_bug")
  end

  it "takes a report from a visitor and from a signed-in person, and shows them to admins and moderators only" do
    get "/bug_reports/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Filed anonymously")
    post "/bug_reports", params: { bug_report: { happened: "The share image is blank on the check page", url: "http://www.example.com/investigations/x" } }
    expect(response).to redirect_to(root_path)
    expect(BugReport.last).to have_attributes(anonymous: true, user: nil, url: "http://www.example.com/investigations/x")
    expect(BugReport.last.reporter).to eq("visitor")

    post "/bug_reports", params: { bug_report: { happened: "   " } }
    expect(response).to have_http_status(:unprocessable_content)

    post session_path, params: { email_address: user.email_address, password: password }
    post "/bug_reports", params: { bug_report: { happened: "Topics page lists a topic twice", expected: "once" } }
    expect(BugReport.order(:created_at).last).to have_attributes(anonymous: false, user: user)

    get "/bug_reports"
    expect(response).to redirect_to(root_path)
    user.update!(moderator: true)
    get "/bug_reports"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("share image is blank").and include("Topics page lists a topic twice")

    # One line each on the list; the filer, the steps and the page it happened on
    # are on the entry's own screen, which is the point of splitting them.
    visitor_report = BugReport.order(:created_at).first
    get "/bug_reports/#{visitor_report.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("visitor").and include("share image is blank")

    patch "/bug_reports/#{visitor_report.id}", params: { status: "ANSWERED", resolution: "Fixed in the share card renderer." }
    expect(visitor_report.reload).to have_attributes(status: "ANSWERED", resolution: "Fixed in the share card renderer.")
    get "/bug_reports/#{visitor_report.id}"
    expect(response.body).to include("Fixed in the share card renderer.")

    # Reopening with an empty box keeps the reason already given.
    patch "/bug_reports/#{visitor_report.id}", params: { status: "OPEN", resolution: "" }
    expect(visitor_report.reload).to have_attributes(status: "OPEN", resolution: "Fixed in the share card renderer.")
    patch "/bug_reports/#{visitor_report.id}", params: { status: "ANSWERED" }
    get "/bug_reports", params: { status: "OPEN" }
    expect(response.body).not_to include("share image is blank")
    get "/bug_reports", params: { status: "ANSWERED" }
    expect(response.body).to include("share image is blank")

    get "/"
    help = response.body[response.body.index("<summary>Help</summary>")..]
    expect(help).to include(">Report a bug<")
    expect(response.body).to include(">Bug reports<")
  end
end
