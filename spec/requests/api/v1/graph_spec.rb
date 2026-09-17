require "rails_helper"

RSpec.describe "Evidence graph over the API (07 Phase 2 #1–#3)", type: :request do
  let(:headers) { { "CONTENT_TYPE" => "application/json" } }
  let(:pair) { register_key(display_name: "Curator").first }

  def post_contribution(action_type, payload, key_pair: pair)
    post "/api/v1/contributions", params: build_envelope(action_type: action_type, payload: payload, key_pair: key_pair).to_json, headers: headers
    expect(response).to have_http_status(:created), response.body
    response.parsed_body
  end

  def created_id(body, kind) = Ledger::Ids.derive(body["contribution"]["id"], kind)

  it "builds source, location, claim, evidence, and support and contradiction links, then reads them as of any seq" do
    content = "Acme press release: 62% of remote workers report higher productivity, according to Acme's 2026 survey."
    source_body = post_contribution("CREATE_SOURCE", { "source_type" => "PRIMARY_TEXT", "title" => "Acme release",
                                                       "content" => content, "content_hash" => Crypto::Hashing.bytes(content) })
    expect(source_body["acceptance"]["action_type"]).to eq("ACCEPT")
    source_id = created_id(source_body, "source")

    excerpt = content[20...81]
    location_body = post_contribution("CREATE_SOURCE_LOCATION", { "source_id" => source_id, "locator_type" => "CHAR_RANGE",
                                                                  "locator" => { "start" => 20, "end" => 81 },
                                                                  "excerpt" => excerpt, "excerpt_hash" => Crypto::Hashing.bytes(excerpt) })
    location_id = created_id(location_body, "location")

    claim_body = post_contribution("CREATE_CLAIM", { "canonical_text" => "The Acme press release states that 62% of remote workers report higher productivity.", "claim_type" => "TEXTUAL", "affirms_not_private_individual" => true })
    claim_id = created_id(claim_body, "claim")
    expect(claim_body["warnings"]).to eq([])

    evidence_body = post_contribution("CREATE_EVIDENCE", { "source_location_id" => location_id, "observation_type" => "DIRECT_TEXT",
                                                           "statement" => "The release states the 62% figure." })
    evidence_id = created_id(evidence_body, "evidence")

    support_body = post_contribution("LINK_EVIDENCE", { "evidence_item_id" => evidence_id, "claim_id" => claim_id, "direction" => "SUPPORT",
                                                        "relevance_strength" => "DIRECT", "interpretive_steps" => 0 })
    support_seq = support_body["contribution"]["seq"]
    contradict_body = post_contribution("LINK_EVIDENCE", { "evidence_item_id" => evidence_id, "claim_id" => claim_id, "direction" => "CONTRADICT",
                                                           "relevance_strength" => "WEAK", "interpretive_steps" => 2, "note" => "reading against the grain" })
    contradict_id = created_id(contradict_body, "link")

    get "/api/v1/claims/#{claim_id}"
    latest = response.parsed_body["claim"]
    expect(latest["status"]).to eq("ACTIVE")
    expect(latest["truth_evaluable"]).to be(true)
    expect(latest["evidence_counts"]).to include("support" => 1, "contradict" => 1, "counted" => 2, "pending" => 0)

    get "/api/v1/claims/#{claim_id}", params: { snapshot_seq: support_seq }
    at_support = response.parsed_body["claim"]
    expect(at_support["snapshot_seq"]).to eq(support_seq)
    expect(at_support["evidence_counts"]).to include("support" => 0, "contradict" => 0, "counted" => 0, "pending" => 1)

    get "/api/v1/claims/#{claim_id}", params: { snapshot_seq: support_seq + 1 }
    expect(response.parsed_body["claim"]["evidence_counts"]).to include("support" => 1, "counted" => 1)

    get "/api/v1/claims/#{claim_id}/evidence"
    counted = response.parsed_body["counted"]
    expect(counted.map { |l| l["direction"] }).to contain_exactly("SUPPORT", "CONTRADICT")
    expect(counted.first["evidence"]["source_location"]["excerpt"]).to eq(excerpt)
    expect(counted.first["evidence"]["source"]["title"]).to eq("Acme release")

    before_invalidation = Contribution.maximum(:seq)
    post_contribution("INVALIDATE", { "contribution_id" => contradict_body["contribution"]["id"], "reason" => "misread" })

    get "/api/v1/claims/#{claim_id}"
    expect(response.parsed_body["claim"]["evidence_counts"]).to include("contradict" => 0, "counted" => 1)
    get "/api/v1/claims/#{claim_id}", params: { snapshot_seq: before_invalidation }
    expect(response.parsed_body["claim"]["evidence_counts"]).to include("contradict" => 1, "counted" => 2)

    get "/api/v1/evidence/#{evidence_id}"
    expect(response.parsed_body["evidence"]["links"].size).to eq(1)
    get "/api/v1/sources/#{source_id}"
    expect(response.parsed_body["source"]["content"]).to eq(content)
    get "/api/v1/sources/#{source_id}/locations"
    expect(response.parsed_body["locations"].first["id"]).to eq(location_id)
    get "/api/v1/claims", params: { q: "productivity" }
    expect(response.parsed_body["claims"].map { |c| c["id"] }).to include(claim_id)
    get "/api/v1/claims/#{claim_id}", params: { snapshot_seq: 99_999 }
    expect(response).to have_http_status(422)
    get "/api/v1/contributors/#{Contributor.find_by!(key_id: pair.key_id).id}"
    expect(response.parsed_body["contributor"]["contributions"]).to include("EPISTEMIC")
  end

  it "reports atomicity warnings without blocking" do
    body = post_contribution("CREATE_CLAIM", { "canonical_text" => "Acme's survey shows remote workers are more productive and happier and save two hours a day, so companies should adopt remote work.", "claim_type" => "TEXTUAL", "affirms_not_private_individual" => true })
    expect(body["warnings"].map { |w| w["code"] }).to include("ATOMICITY_CONJUNCTION", "ATOMICITY_INFERENCE")
    expect(Claim.find(created_id(body, "claim"))).to be_persisted
  end
end
