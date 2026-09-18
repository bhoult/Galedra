require "rails_helper"

RSpec.describe "The write link and idempotent recording (after Stage 14)", type: :request do
  before { release_models }

  let!(:token) { Assistants::Connect.call(name: "Browsing GPT", provider: "openai").last }

  def bundle
    JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about").tap do |b|
      b["sources"].each { |s| s["retrieved_at"] = "2026-09-18T12:00:00Z" }
    end
  end

  def encoded(b) = Base64.urlsafe_encode64(JSON.generate(b), padding: false)

  it "records on GET with the token and a base64url bundle, once, and replays the receipt afterwards" do
    count = Contribution.count
    get "/api/v1/investigations/record", params: { token: token, bundle: encoded(bundle) }
    expect(response).to have_http_status(:created)
    first = response.parsed_body
    expect(first["recorded"]).to be(true)
    expect(first["replayed"]).to be(false)
    expect(first["claims"].first.dig("card", "plain", "headline")).to match(/against/)
    appended = Contribution.count - count

    get "/api/v1/investigations/record", params: { token: token, bundle: encoded(bundle) }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["replayed"]).to be(true)
    expect(response.parsed_body["receipt_id"]).to eq(first["receipt_id"])
    expect(response.parsed_body["claims"].first["id"]).to eq(first["claims"].first["id"])
    expect(Contribution.count - count).to eq(appended)

    post "/api/v1/investigations", params: bundle.to_json, headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["replayed"]).to be(true)
    expect(Contribution.count - count).to eq(appended)
  end

  it "records without any token as an anonymous assistant keyed to the caller for the day" do
    tokens = AssistantToken.count
    get "/api/v1/investigations/record", params: { bundle: encoded(bundle) }
    expect(response).to have_http_status(:created)
    anonymous = AssistantToken.find_by!(source_key: Digest::SHA256.hexdigest("127.0.0.1|#{Date.current}"))
    expect(anonymous.principal).to be_anonymous
    expect(anonymous.software["agent_name"]).to eq("Anonymous assistant")
    expect(response.parsed_body["claims"].first.dig("card", "labels")).to include(a_string_including("anonymous contributor"))

    get "/api/v1/investigations/record", params: { bundle: encoded(bundle) }
    expect(response.parsed_body["replayed"]).to be(true)
    get "/api/v1/investigations/record/#{encoded(bundle)}"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["replayed"]).to be(true)
    post "/api/v1/investigations", params: bundle.merge("claims" => [ { "handle" => "q", "text" => "Tokenless POST.", "type" => "TEXTUAL" } ], "links" => [], "evidence" => [], "excerpts" => [], "sources" => []).to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:created)
    expect(AssistantToken.count).to eq(tokens + 1)

    post "/api/v1/custodied/contributions", params: { action_type: "CREATE_CLAIM", payload: claim_payload("Raw write.") }.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "refuses a wrong token, a bad bundle, and a revoked token" do
    get "/api/v1/investigations/record", params: { token: "gal_wrong", bundle: encoded(bundle) }
    expect(response).to have_http_status(:unauthorized)

    get "/api/v1/investigations/record", params: { token: token, bundle: "" }
    expect(response).to have_http_status(422)
    expect(response.parsed_body["errors"].first["path"]).to eq("$.bundle")

    get "/api/v1/investigations/record", params: { token: token, bundle: "not*base64" }
    expect(response).to have_http_status(422)

    get "/api/v1/investigations/record", params: { token: token, bundle: JSON.generate(bundle) }
    expect(response).to have_http_status(:created)

    Assistants::Revoke.call(AssistantToken.find_by_token(token))
    get "/api/v1/investigations/record", params: { token: token, bundle: encoded(bundle.merge("claims" => [ { "handle" => "z", "text" => "After revocation.", "type" => "TEXTUAL" } ], "links" => [], "evidence" => [], "excerpts" => [], "sources" => [])) }
    expect(response).to have_http_status(:unauthorized)
  end
end
