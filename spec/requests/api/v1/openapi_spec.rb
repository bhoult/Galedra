require "rails_helper"

RSpec.describe "OpenAPI document (Stage 14)", type: :request do
  before { release_models }

  it "is a valid 3.1 document whose every path responds (#2)" do
    get "/api/v1/openapi.json"
    expect(response).to have_http_status(:ok)
    doc = response.parsed_body
    expect(doc["openapi"]).to eq("3.1.0")
    expect(doc["info"]).to include("title" => "Galedra")
    expect(doc["servers"].first["url"]).to eq("http://www.example.com")
    expect(doc.dig("components", "securitySchemes", "assistantToken", "scheme")).to eq("bearer")
    expect(doc["paths"].keys).to include("/api/v1/investigations", "/api/v1/claims", "/api/v1/claims/{id}/why")
    doc["paths"].each_value do |ops|
      ops.each_value { |op| expect(op["operationId"]).to be_present }
    end

    curator, = register_key(display_name: "Curator")
    source = create_source(curator)
    claim = create_claim(curator, "Every path answers.")
    task = create_task("QUALIFIER_CHECK", claim)
    ids = { "/api/v1/claims/{id}" => claim.id, "/api/v1/sources/{id}" => source.id, "/api/v1/contributions/{id}" => claim.contribution_id, "/api/v1/tasks/{id}" => task.id }
    doc["paths"].each do |path, ops|
      next unless ops.key?("get")

      id = ids.find { |prefix, _| path.start_with?(prefix) }&.last || claim.id
      get path.sub("{id}", id)
      expect(response).to have_http_status(:ok), "#{path} -> #{response.status}"
    end

    token = Assistants::Connect.call(name: "Claude", provider: "anthropic").last
    post "/api/v1/custodied/contributions", params: { action_type: "CREATE_CLAIM", payload: claim_payload("A custodied write.") }.to_json,
                                            headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:created)

    get "/api/v1/meta"
    expect(response.parsed_body).to include("openapi_url" => "http://www.example.com/api/v1/openapi.json", "mcp_url" => "http://www.example.com/mcp")
  end
end
