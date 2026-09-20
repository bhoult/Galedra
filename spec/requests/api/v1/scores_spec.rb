require "rails_helper"

RSpec.describe "Score endpoints (spec 06 §2)", type: :request do
  let(:headers) { { "CONTENT_TYPE" => "application/json" } }

  before { release_models }

  it "serves score, trace, compare, model list, snapshots, and the assessment block, always with snapshot and model" do
    curator, = register_key
    source = create_source(curator, type: "DATASET", content: "Survey: 62% of 400 respondents reported higher productivity.")
    evidence = create_evidence(curator, create_location(curator, source), observation: "DATASET_RESULT")
    causal = create_claim(curator, "Remote work causes higher productivity.", type: "CAUSAL")
    link_evidence(curator, evidence, causal, strength: "WEAK", steps: 2)
    normative = create_claim(curator, "Companies should adopt remote work.", type: "NORMATIVE")
    seq = Contribution.maximum(:seq)

    get "/api/v1/claims/#{causal.id}/score"
    body = response.parsed_body
    expect(body).to include("snapshot_seq" => seq, "model" => Scoring::Registry.default_model.full_name)
    expect(body["assessment"]).to include("assessment_state" => "UNRESOLVED", "probability" => "0.3792", "model_dependent" => true, "stability" => "LOW", "provisional" => true)

    get "/api/v1/claims/#{causal.id}/score", params: { model: "ledger-strict@0.1.0" }
    expect(response.parsed_body["assessment"]).to include("assessment_state" => "NOT_APPLICABLE", "probability" => nil, "not_applicable_reason" => "NOT_SCORED_BY_MODEL")

    get "/api/v1/claims/#{causal.id}/trace"
    expect(response.parsed_body["trace"]).to include("model" => Scoring::Registry.default_model.full_name, "snapshot_seq" => seq, "probability" => "0.3792")
    expect(response.parsed_body["canonical_trace"]).to start_with("{")

    get "/api/v1/claims/#{causal.id}/compare", params: { models: "ledger-default@0.1.0,ledger-strict@0.1.0" }
    expect(response.parsed_body["state_change"]).to eq("from" => "UNRESOLVED", "to" => "NOT_APPLICABLE")
    expect(response.parsed_body["responsible_config_keys"]).to include("scored_types")

    get "/api/v1/claims/#{normative.id}/score"
    expect(response.parsed_body["assessment"]).to include("assessment_state" => "NOT_APPLICABLE", "probability" => nil, "not_applicable_reason" => "NORMATIVE_OR_VALUE")

    get "/api/v1/claims/#{causal.id}"
    expect(response.parsed_body["claim"]["assessment"]).to include("assessment_state" => "UNRESOLVED", "snapshot_seq" => seq, "model" => Scoring::Registry.default_model.full_name)
    get "/api/v1/claims", params: { state: "NOT_APPLICABLE" }
    expect(response.parsed_body["claims"].map { |c| c["id"] }).to eq([ normative.id ])
    get "/api/v1/claims", params: { state: "NOT_APPLICABLE", model: "ledger-strict@0.1.0" }
    expect(response.parsed_body["claims"].map { |c| c["id"] }).to contain_exactly(normative.id, causal.id)

    get "/api/v1/claims/#{causal.id}/score", params: { model: "ledger-nonexistent@9.9.9" }
    expect(response).to have_http_status(422)
    expect(response.parsed_body["errors"].first["code"]).to eq("MODEL_UNKNOWN")

    get "/api/v1/scoring-models"
    expect(response.parsed_body["default"]).to eq(Scoring::Registry.default_model.full_name)
    expect(response.parsed_body["models"].map { |m| m["name"] }).to match_array(Scoring::Registry.released.map(&:full_name))
    get "/api/v1/meta"
    expect(response.parsed_body).to include("default_model" => Scoring::Registry.default_model.full_name)
    expect(response.parsed_body["scoring_models"]).to match_array(Scoring::Registry.released.map(&:full_name))

    get "/api/v1/snapshots/#{seq}"
    expect(response.parsed_body).to include("seq" => seq, "entry_hash" => Contribution.find_by!(seq: seq).entry_hash, "pinned" => false)
    expect(response.parsed_body["claim_score_digest"]).to start_with("sha256:")
    expect(response.parsed_body["claim_score_digest"]).to eq(Snapshots::Digest.call(seq))
  end

  it "returns the quarantine stub instead of a score for a quarantined claim" do
    curator, = register_key
    moderator, = register_moderator
    claim = create_claim(curator, "About a private person.")
    quarantine(moderator, claim)
    get "/api/v1/claims/#{claim.id}/score"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("assessment_state" => "QUARANTINED", "quarantined" => true)
    expect(response.body).not_to include("private person")
  end

  it "lets only moderators pin snapshots and trigger recomputes, with signed requests" do
    include ActiveJob::TestHelper
    moderator, = register_moderator
    curator, = register_key
    seq = Contribution.maximum(:seq)

    post "/api/v1/admin/snapshots", params: Admin::Request.build(payload: { "seq" => seq, "label" => "S1" }, key_pair: moderator).to_json, headers: headers
    expect(response).to have_http_status(:created), response.body
    expect(GraphSnapshot.find_by(seq: seq).label).to eq("S1")
    get "/api/v1/snapshots"
    expect(response.parsed_body["snapshots"].map { |s| s["seq"] }).to eq([ seq ])

    post "/api/v1/admin/snapshots", params: Admin::Request.build(payload: { "seq" => seq }, key_pair: curator).to_json, headers: headers
    expect(response).to have_http_status(422)
    expect(response.parsed_body["errors"].first["code"]).to eq("NOT_AUTHORIZED")

    stale = Admin::Request.build(payload: { "seq" => seq }, key_pair: moderator, client_created_at: 1.hour.ago)
    post "/api/v1/admin/snapshots", params: stale.to_json, headers: headers
    expect(response.parsed_body["errors"].first["code"]).to eq("SCHEMA_INVALID")

    tampered = Admin::Request.build(payload: { "seq" => seq }, key_pair: moderator).merge("payload" => { "seq" => 0 })
    post "/api/v1/admin/snapshots", params: tampered.to_json, headers: headers
    expect(response.parsed_body["errors"].first["code"]).to eq("SIGNATURE_INVALID")

    post "/api/v1/admin/recompute", params: Admin::Request.build(payload: {}, key_pair: moderator).to_json, headers: headers
    expect(response).to have_http_status(:accepted)
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |j| j["job_class"] }).to include("RecomputeAllScoresJob")
  end
end
