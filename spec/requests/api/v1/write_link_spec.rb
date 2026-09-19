require "rails_helper"

RSpec.describe "Idempotent and anonymous recording over POST (after Stage 14; the GET write link was removed 2026-09-19)", type: :request do
  before { release_models }

  let!(:token) { Assistants::Connect.call(name: "Browsing GPT", provider: "openai").last }

  def bundle
    JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about").tap do |b|
      b["sources"].each { |s| s["retrieved_at"] = "2026-09-18T12:00:00Z" }
    end
  end

  def post_bundle(b, tok = nil)
    headers = { "CONTENT_TYPE" => "application/json" }
    headers["Authorization"] = "Bearer #{tok}" if tok
    post "/api/v1/investigations", params: b.to_json, headers: headers
  end

  it "records once and replays the receipt for the same assistant and bundle" do
    count = Contribution.count
    post_bundle(bundle, token)
    expect(response).to have_http_status(:created)
    first = response.parsed_body
    expect(first["recorded"]).to be(true)
    expect(first["replayed"]).to be(false)
    appended = Contribution.count - count

    post_bundle(bundle, token)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["replayed"]).to be(true)
    expect(response.parsed_body["receipt_id"]).to eq(first["receipt_id"])
    expect(response.parsed_body["claims"].first["id"]).to eq(first["claims"].first["id"])
    expect(Contribution.count - count).to eq(appended)
  end

  it "records without any token as an anonymous assistant keyed to the caller for the day, while raw writes still need a token" do
    tokens = AssistantToken.count
    post_bundle(bundle)
    expect(response).to have_http_status(:created)
    anonymous = AssistantToken.find_by!(source_key: Digest::SHA256.hexdigest("127.0.0.1|#{Date.current}"))
    expect(anonymous.principal).to be_anonymous
    expect(anonymous.software["agent_name"]).to eq("Anonymous assistant")
    expect(response.parsed_body["claims"].first.dig("card", "labels")).to include(a_string_including("anonymous contributor"))
    post_bundle(bundle)
    expect(response.parsed_body["replayed"]).to be(true)
    expect(AssistantToken.count).to eq(tokens + 1)

    post "/api/v1/custodied/contributions", params: { action_type: "CREATE_CLAIM", payload: claim_payload("Raw write.") }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "refuses a wrong or revoked token, and no longer records on GET" do
    post_bundle(bundle, "gal_wrong")
    expect(response).to have_http_status(:unauthorized)

    Assistants::Revoke.call(AssistantToken.find_by_token(token))
    post_bundle(bundle.merge("claims" => [ { "handle" => "z", "text" => "After revocation.", "type" => "TEXTUAL" } ], "links" => [], "evidence" => [], "excerpts" => [], "sources" => []), token)
    expect(response).to have_http_status(:unauthorized)

    encoded = Base64.urlsafe_encode64(JSON.generate(bundle), padding: false)
    count = Contribution.count
    get "/api/v1/investigations/record", params: { bundle: encoded }
    expect(response).to have_http_status(:not_found)
    get "/api/v1/investigations/record/#{encoded}"
    expect(response).to have_http_status(:not_found)
    expect(Contribution.count).to eq(count)
  end
end
