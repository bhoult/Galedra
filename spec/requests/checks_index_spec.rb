require "rails_helper"

RSpec.describe "Finding a recorded check again (owner request, 2026-09-19)", type: :request do
  before { release_models }

  let(:token) { Assistants::Connect.call(name: "Claude", provider: "anthropic").first }

  def record(statement)
    bundle = JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about")
    bundle["sources"].each { |s| s["retrieved_at"] = Time.now.utc.iso8601 }
    bundle["statement"] = statement
    bundle["claims"].each_with_index { |c, i| c["text"] = "#{c['text']} (#{statement[0, 12]} #{i})" }
    # The two statements reuse the fixture's claims, so the second is caught as
    # a near-duplicate; recording it anyway is what the duplicates page does.
    bundle["on_duplicate"] = "create"
    result = Investigations::Record.call(token, bundle, base_url: "http://www.example.com")
    result.merge(id: result.dig(:share, :url).to_s[%r{/investigations/(.+)\z}, 1])
  end

  it "lists every check newest first, with its reading, and links each claim back to the ones it was part of" do
    older = record("The first statement anyone asked about.")
    newer = record("The second statement, asked about later.")
    expect(older[:recorded]).to be(true)
    expect(newer[:recorded]).to be(true)
    Investigation.find(older[:id]).update!(created_at: 2.days.ago)

    get "/investigations"
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include("The first statement anyone asked about.").and include("The second statement, asked about later.")
    # Newest first, so the later one comes higher up the page.
    expect(body.index("The second statement")).to be < body.index("The first statement")
    # The reading of the whole statement, not just a list of links.
    expect(body).to include("checkable").and include("provisional until audited")
    expect(body).to include("/investigations/#{older[:id]}")

    # It is reachable without knowing the link, which was the whole problem.
    get "/"
    expect(response.body).to include(">Checks<")

    claim_id = Investigation.find(newer[:id]).claim_ids.first
    get "/claims/#{claim_id}"
    expect(response.body).to include("Checked as part of")
    expect(response.body).to include("The second statement, asked about later.")
    expect(response.body).to include("/investigations/#{newer[:id]}")
    # A claim belongs to the check it came from, and not to the other one.
    expect(response.body).not_to include("/investigations/#{older[:id]}")
  end

  it "shows nothing rather than an error when no check has been recorded" do
    get "/investigations"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nothing checked yet.")
  end
end
