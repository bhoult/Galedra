require "rails_helper"

RSpec.describe "GET /", type: :request do
  let(:constitution) { Governance::Constitution.new }

  it "shows signed-out visitors the introduction, the use cases, and the whole constitution" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("A heap of witness.")
    expect(response.body).to include("Use cases")
    expect(response.body).to include("Verify the citations and statistics in an AI draft")
    expect(response.body).to include("Journal of Distributed Work Research, 2025")
    expect(response.body).to include("does not seek to own truth")
    expect(response.body).to include("Read the constitution")
    expect(response.body).not_to include("Article XXV")
    expect(response.body).to include(constitution.digest)
    expect(response.body).to include("graph-background")
    expect(response.body).not_to include("Recent audits")
    expect(response.body).to include(">FAQ<")
    expect(response.body).not_to include(">Task board<")
  end

  it "answers frequently asked questions" do
    get "/faq"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Is Galedra a fact-checker?")
    expect(response.body).to include("What does the number mean?")
  end

  it "shows signed-in users the dashboard instead" do
    user = User.create!(email_address: "reader@example.com", password: "correct horse battery staple")
    post session_path, params: { email_address: user.email_address, password: "correct horse battery staple" }
    get "/"

    expect(response.body).to include("Recent audits")
    expect(response.body).to include("Analyze text")
    expect(response.body).not_to include("A heap of witness.")
    expect(response.body).to include(constitution.digest)
  end

  it "renders the constitution on one page from the hashed bytes" do
    get "/constitution"

    expect(response).to have_http_status(:ok)
    expect(constitution.articles.size).to eq(25)
    constitution.articles.each { |a| expect(response.body).to include(ERB::Util.html_escape(a.title)) }
    expect(response.body).to include("Article XXV")
    expect(response.body).to include("Foundational Statement")
  end
end
