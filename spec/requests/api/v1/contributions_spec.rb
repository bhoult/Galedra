require "rails_helper"

RSpec.describe "Contributions API", type: :request do
  let(:headers) { { "CONTENT_TYPE" => "application/json" } }

  it "appends a signed envelope, then returns the original on resubmission" do
    pair = key_pair
    envelope = build_envelope(action_type: "REGISTER_KEY", key_pair: pair, payload: { "public_key" => pair.public_key, "kind" => "HUMAN" })

    post "/api/v1/contributions", params: envelope.to_json, headers: headers
    expect(response).to have_http_status(:created)
    first = response.parsed_body["contribution"]
    expect(first["seq"]).to eq(Contribution.maximum(:seq))
    expect(first["entry_hash"]).to start_with("sha256:")
    expect(first["current_status"]).to eq("ACCEPTED")
    expect(first["received_at"]).to match(/\.\d{6}Z\z/)

    post "/api/v1/contributions", params: envelope.to_json, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["contribution"]["id"]).to eq(first["id"])
  end

  it "rejects invalid envelopes with the spec's error format and logs nothing" do
    count = Contribution.count
    post "/api/v1/contributions", params: { "protocol" => "nope" }.to_json, headers: headers
    expect(response).to have_http_status(422)
    error = response.parsed_body["errors"].first
    expect(error).to include("code" => "SCHEMA_INVALID", "path" => "$")
    expect(error["detail"]).to be_present

    post "/api/v1/contributions", params: "not json", headers: headers
    expect(response).to have_http_status(422)
    expect(Contribution.count).to eq(count)
  end

  it "shows an entry with its envelope and verifies it" do
    pair, = register_key
    c = Contribution.find_by!(signer_key_id: pair.key_id)

    get "/api/v1/contributions/#{c.id}"
    body = response.parsed_body["contribution"]
    expect(body["envelope"]["signature"]).to eq(c.signature)
    expect(body["prev_hash"]).to eq(c.prev_hash)
    expect(response.parsed_body["audits"]).to eq([])

    get "/api/v1/contributions/#{c.id}/verify"
    expect(response.parsed_body).to eq("client_signature_ok" => true, "server_signature_ok" => true, "chain_ok" => true)

    get "/api/v1/contributions/#{SecureRandom.uuid}"
    expect(response).to have_http_status(:not_found)
  end

  it "streams the log for mirroring and reports the head in meta" do
    register_key
    register_key
    get "/api/v1/log", params: { after_seq: 0, limit: 1 }
    entries = response.parsed_body["entries"]
    expect(entries.size).to eq(1)
    expect(entries.first["seq"]).to eq(1)
    expect(entries.first["envelope"]).to be_a(Hash)

    get "/api/v1/log", params: { after_seq: entries.first["seq"] }
    expect(response.parsed_body["entries"].map { |e| e["seq"] }).to eq((2..Contribution.maximum(:seq)).to_a)

    get "/api/v1/meta"
    expect(response.parsed_body["current_seq"]).to eq(Contribution.maximum(:seq))
    expect(response.parsed_body["chain_head"]).to eq(Contribution.in_order.last.entry_hash)
  end
end
