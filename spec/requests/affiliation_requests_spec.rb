require "rails_helper"

RSpec.describe "Missing affiliations: request, dedupe, settle (owner request, 2026-09-19)", type: :request do
  let(:password) { "correct horse battery staple" }

  def sign_up(email)
    post "/users", params: { user: { email_address: email, password: password, password_confirmation: password } }
    User.find_by!(email_address: email)
  end

  it "maps short forms and synonyms to existing affiliations without a person, and proposes similar ones" do
    expect(Affiliations::Resolve.call("dem")).to include(slug: "democrat", confidence: "ALIAS")
    expect(Affiliations::Resolve.call("Democrat")).to include(slug: "democrat", confidence: "EXACT")
    expect(Affiliations::Resolve.call("GOP")).to include(slug: "republican", confidence: "ALIAS")
    expect(Affiliations::Resolve.call("millenials")).to include(slug: "millennial", confidence: "SIMILAR")
    expect(Affiliations::Resolve.call("Arkansan")).to include(confidence: "NONE")
    expect(Affiliations::Resolve.call("")).to include(confidence: "NONE")
  end

  it "applies an automatic match to the account and leaves the rest to an admin, who settles every requester at once" do
    admin = sign_up("admin@example.com")
    delete "/session"
    me = sign_up("me@example.com")
    post "/affiliation_requests", params: { text: "dem" }
    expect(flash[:notice]).to include("Democrat")
    expect(me.user_affiliations.pluck(:affiliation)).to eq([ "democrat" ])
    expect(me.affiliation_requests.first).to have_attributes(status: "MERGED", resolved_slug: "democrat", confidence: "ALIAS")

    post "/affiliation_requests", params: { text: "Arkansan" }
    expect(flash[:notice]).to include("An admin")
    expect(me.affiliation_requests.pending.first).to have_attributes(confidence: "NONE", normalized: "arkansan")
    delete "/session"
    other = sign_up("other@example.com")
    post "/affiliation_requests", params: { text: "arkansan!" }
    post "/affiliation_requests", params: { text: "ar" }
    get "/admin/affiliation_requests"
    expect(response).to redirect_to(root_path)
    delete "/session"

    post "/session", params: { email_address: admin.email_address, password: password }
    get "/admin/affiliation_requests"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Arkansan").and include(">2<")

    post "/admin/affiliation_requests/add", params: { normalized: "arkansan", label: "Arkansan", group_slug: "nationality" }
    expect(CustomAffiliation.find_by(slug: "arkansan")).to have_attributes(label: "Arkansan", group_slug: "nationality")
    expect(Affiliations.valid?("arkansan")).to be(true)
    expect(me.user_affiliations.pluck(:affiliation)).to match_array(%w[democrat arkansan])
    expect(other.user_affiliations.pluck(:affiliation)).to eq([ "arkansan" ])
    expect(AffiliationRequest.where(normalized: "arkansan").pluck(:status).uniq).to eq([ "ADDED" ])

    # Now "ar" can be merged into the new entry, and a later "arkansan" is an exact match.
    post "/admin/affiliation_requests/merge", params: { normalized: "ar", slug: "arkansan" }
    expect(AffiliationRequest.find_by(normalized: "ar")).to have_attributes(status: "MERGED", resolved_slug: "arkansan", resolved_by: admin)
    expect(Affiliations::Resolve.call("Arkansan")).to include(slug: "arkansan", confidence: "EXACT")

    post "/admin/affiliation_requests/add", params: { normalized: "x", label: "Democrat", group_slug: "politics" }
    expect(flash[:alert]).to include("curated")
    post "/affiliation_requests", params: { text: "Quaker" }
    post "/admin/affiliation_requests/decline", params: { normalized: "quaker" }
    expect(AffiliationRequest.find_by(normalized: "quaker").status).to eq("DECLINED")

    get "/account"
    expect(response.body).to include("Arkansan").and include("Missing one?")
  end

  it "settles a request the deduplicator could not by the agreement of assistants, never the requester's own" do
    password = "correct horse battery staple"
    me = sign_up("me@example.com")
    post "/affiliation_requests", params: { text: "Arkansan" }
    delete "/session"
    mine = Assistants::Connect.call(user: me, name: "Mine", provider: "anthropic").last
    a = Assistants::Connect.call(user: User.create!(email_address: "a@example.com", password: password), name: "A", provider: "anthropic").last
    b = Assistants::Connect.call(user: User.create!(email_address: "b@example.com", password: password), name: "B", provider: "openai").last
    call = lambda do |name, args, tok|
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: args } }.to_json,
                   headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{tok}" }
      [ response.parsed_body.dig("result", "structuredContent"), response.parsed_body.dig("result", "isError") ]
    end

    data, = call.call("next_affiliation_review", {}, mine)
    expect(data["available"]).to be(false)
    data, err = call.call("submit_affiliation_review", { normalized: "arkansan", verdict: "DECLINE" }, mine)
    expect(err).to be(true)
    expect(data["errors"].first["code"]).to eq("NOT_AUTHORIZED")

    packet, err = call.call("next_affiliation_review", {}, a)
    expect(err).to be(false), packet.inspect
    expect(packet).to include("available" => true, "normalized" => "arkansan", "asked_for" => "Arkansan", "people" => 1)
    expect(packet["vocabulary"].map { |g| g["group"] }).to include("nationality")
    data, = call.call("submit_affiliation_review", { normalized: "arkansan", verdict: "ADD", label: "Arkansan", group_slug: "nationality", reason: "US state" }, a)
    expect(data).to include("settled" => false, "status" => "PENDING")
    data, = call.call("list_tasks", {}, a)
    expect(data["affiliation_reviews_pending"]).to eq(1)
    data, = call.call("submit_affiliation_review", { normalized: "arkansan", verdict: "ADD", label: "arkansan", group_slug: "other" }, b)
    expect(data).to include("settled" => true, "status" => "ADDED", "became" => "Arkansan")
    expect(CustomAffiliation.find_by(slug: "arkansan")).to have_attributes(label: "Arkansan", group_slug: "nationality")
    expect(me.user_affiliations.pluck(:affiliation)).to eq([ "arkansan" ])

    # A lone verdict on a second request stands after two days.
    AffiliationRequest.file!(user: me, text: "Gen Jones")
    call.call("submit_affiliation_review", { normalized: "gen jones", verdict: "MERGE", slug: "boomer", reason: "late boomers" }, a)
    expect(AffiliationRequest.find_by(normalized: "gen jones").status).to eq("PENDING")
    ReviewVerdict.where(subject_key: "gen jones").update_all(created_at: 3.days.ago)
    SettleLoneVerdictsJob.perform_now
    expect(AffiliationRequest.find_by(normalized: "gen jones")).to have_attributes(status: "MERGED", resolved_slug: "boomer")
    expect(me.user_affiliations.pluck(:affiliation)).to match_array(%w[arkansan boomer])
  end
end
