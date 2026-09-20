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

    patch "/bug_reports/#{visitor_report.id}", params: { status: "DONE" }
    expect(visitor_report.reload.status).to eq("DONE")
    get "/bug_reports", params: { status: "OPEN" }
    expect(response.body).not_to include("share image is blank")
    get "/bug_reports", params: { status: "DONE" }
    expect(response.body).to include("share image is blank")

    get "/"
    help = response.body[response.body.index("<summary>Help</summary>")..]
    expect(help).to include(">Report a bug<")
    expect(response.body).to include(">Bug reports<")
  end
end
