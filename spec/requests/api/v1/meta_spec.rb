require "rails_helper"

RSpec.describe "GET /api/v1/meta", type: :request do
  it "publishes the constitution version and hash" do
    get "/api/v1/meta"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["constitution_version"]).to eq("1.0.0")
    expect(body["constitution_hash"]).to eq(Governance::Constitution.new.digest)
  end

  it "matches sha256sum of CONSTITUTION.md" do
    get "/api/v1/meta"

    hex = Digest::SHA256.file(Rails.root.join("CONSTITUTION.md")).hexdigest
    expect(response.parsed_body["constitution_hash"]).to eq("sha256:#{hex}")
  end

  it "publishes the system key id and public key" do
    get "/api/v1/meta"

    expect(response.parsed_body["system_key_id"]).to eq(Crypto::SystemKey.key_id)
    expect(response.parsed_body["system_public_key"]).to eq(Crypto::SystemKey.public_key)
  end
end
