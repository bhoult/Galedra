require "rails_helper"

RSpec.describe "OpenAPI document (Stage 14)", type: :request do
  include LedgerHelpers
  include GraphHelpers
  before { release_models }

  # Routes and the document write a path parameter differently (:id against
  # {id}); compare them in one spelling.
  def normalize(path) = path.gsub(/[:{]([a-z_]+)\}?/) { "{#{Regexp.last_match(1)}}" }

  def routed_operations
    Rails.application.routes.routes.filter_map { |r|
      path = normalize("/#{r.path.spec.to_s.sub(/\(\.:format\)\z/, '').delete_prefix('/')}")
      [ r.verb.to_s.downcase, path ] if path.start_with?("/api/v1")
    }.uniq
  end

  it "describes every route under /api/v1, so an endpoint cannot be added without documenting it (#2)" do
    paths = Api::Openapi.document("http://x")[:paths]
    undescribed = routed_operations.reject { |verb, path| paths.dig(path, verb.to_sym) }
    expect(undescribed).to be_empty,
                           "these routes are not in Api::Openapi.document:\n" +
                           undescribed.map { |verb, path| "  #{verb.upcase} #{path}" }.join("\n") +
                           "\n\nAdd them to read_paths or write_paths."
  end

  it "describes nothing that is not routed" do
    doc_ops = Api::Openapi.document("http://x")[:paths].flat_map { |path, ops| ops.keys.map { |verb| [ verb.to_s, path ] } }
    expect(doc_ops - routed_operations).to be_empty
  end

  it "tags every operation with a declared tag, so the renderer groups them" do
    doc = Api::Openapi.document("http://x")
    declared = doc[:tags].map { |t| t[:name] }
    expect(declared).to eq(Api::Openapi::TAGS.map { |t| t[:name] })
    doc[:paths].each do |path, ops|
      ops.each do |verb, op|
        expect(op[:tags]).to be_present, "#{verb.upcase} #{path} has no tag"
        expect(declared).to include(*op[:tags])
      end
    end
    expect(Api::Openapi.reference.sum { |g| g[:rows].size }).to eq(doc[:paths].sum { |_, ops| ops.size })
  end

  it "is a valid 3.1 document whose every read responds (#2)" do
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

    pair, curator = register_key(display_name: "Curator")
    source = create_source(pair)
    location = create_location(pair, source)
    claim = create_claim(pair, "Every path answers.")
    premise = create_claim(pair, "The premise holds.")
    second = create_claim(pair, "The second premise holds.")
    evidence = create_evidence(pair, location)
    link_evidence(pair, evidence, claim)
    task = create_task("QUALIFIER_CHECK", claim)
    section = Section.find(Ledger::Ids.derive(
      append(action_type: "CREATE_SECTION", key_pair: pair,
             payload: { "source_id" => source.id, "sections" => [ { "heading" => "A heading" } ] }).contribution.id, "section", 0))
    inference = Inference.find(Ledger::Ids.derive(
      append(action_type: "CREATE_INFERENCE", key_pair: pair,
             payload: { "conclusion_claim_id" => claim.id, "premises" => [ { "claim_id" => premise.id, "polarity" => "HOLDS" }, { "claim_id" => second.id, "polarity" => "HOLDS" } ],
                        "inference_type" => "DEDUCTIVE", "rule" => "If both premises hold the conclusion follows.",
                        "strength" => "ENTAILS", "affirms_not_private_individual" => true }).contribution.id, "inference"))

    values = {
      "/api/v1/claims/{id}" => claim.id, "/api/v1/sources/{id}" => source.id, "/api/v1/evidence/{id}" => evidence.id,
      "/api/v1/contributions/{id}" => claim.contribution_id, "/api/v1/tasks/{id}" => task.id,
      "/api/v1/sections/{id}" => section.id, "/api/v1/inferences/{id}" => inference.id,
      "/api/v1/contributors/{id}" => curator.id, "/api/v1/snapshots/{seq}" => Contribution.maximum(:seq),
      "/api/v1/schemas/{name}" => "eir-contribution-v1"
    }

    doc["paths"].each do |path, ops|
      next unless ops.key?("get")

      value = values.select { |prefix, _| path.start_with?(prefix) }.max_by { |prefix, _| prefix.length }&.last
      expect(value).to be_present, "#{path} has no fixture; add one to values" if path.include?("{")
      get path.gsub(/\{\w+\}/, value.to_s)
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
