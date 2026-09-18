require "rails_helper"

RSpec.describe "Connected assistants (Stage 12)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before { release_models }

  let(:headers) { { "CONTENT_TYPE" => "application/json" } }

  def bearer(token) = headers.merge("Authorization" => "Bearer #{token}")

  def custodied_write(token, action_type, payload)
    post "/api/v1/custodied/contributions", params: { action_type: action_type, payload: payload }.to_json, headers: bearer(token)
    response
  end

  it "mints an anonymous token that delegates from a fresh ANONYMOUS key, and a signed-in token from the user's key (#1)" do
    post "/api/v1/assistants", params: { assistant: { name: "Grok", provider: "xai", model: "grok-4" } }.to_json, headers: headers
    expect(response).to have_http_status(:created)
    body = response.parsed_body
    expect(body["token"]).to start_with("gal_")
    expect(body["assistant"]).to include("name" => "Grok", "provider" => "xai", "principal_tier" => "ANONYMOUS", "revoked" => false)

    record = AssistantToken.find_by_token(body["token"])
    expect(record.agent).to be_agent
    expect(record.agent).to be_server_custodied
    expect(record.principal).to be_anonymous
    expect(record.principal.custodied_key.user).to be_nil
    delegation = Contribution.find_by!(action_type: "DELEGATE", signer_key_id: record.principal.key_id)
    expect(delegation.payload["delegate_key_id"]).to eq(record.agent.key_id)
    expect(delegation.custody).to eq("SERVER")
    expect(AssistantToken.count).to eq(1)

    user = User.create!(email_address: "me@example.com", password: "correct horse battery staple")
    signed_in, = Assistants::Connect.call(user: user, name: "Claude", provider: "anthropic")
    expect(signed_in.principal).to eq(user.custodied_key.contributor)
    expect(signed_in.principal.identity_tier).to eq("PSEUDONYMOUS")
    expect(signed_in.agent.display_name).to eq("Claude for me")
  end

  it "signs custodied writes with the agent key under the delegation, naming the assistant, and the chain verifies (#2)" do
    post "/api/v1/assistants", params: { assistant: { name: "ChatGPT", provider: "openai" } }.to_json, headers: headers
    token = response.parsed_body["token"]
    record = AssistantToken.find_by_token(token)

    custodied_write(token, "CREATE_CLAIM", claim_payload("Water boils at 100 degrees Celsius at sea level.", type: "QUANTITATIVE"))
    expect(response).to have_http_status(:created)
    contribution = Contribution.find(response.parsed_body["contribution"]["id"])
    expect(contribution.signer_key_id).to eq(record.agent.key_id)
    expect(contribution.custody).to eq("SERVER")
    expect(contribution.envelope["delegation_id"]).to eq(record.delegation_id)
    expect(contribution.software).to include("agent_name" => "ChatGPT", "model_provider" => "openai")
    expect(contribution.principal_contributor).to eq(record.principal)
    expect(contribution.current_status).to eq("ACCEPTED")
    expect(Ledger::Verify.entry(contribution)).to include(client_signature_ok: true, server_signature_ok: true, chain_ok: true)
    expect(Ledger::Verify.call.status).to eq("CHAIN_VERIFIED")
    expect(record.reload.last_used_at).to be_present

    custodied_write(token, "CREATE_CLAIM", { "canonical_text" => "" })
    expect(response).to have_http_status(422)
    expect(response.parsed_body["errors"].first["code"]).to eq("SCHEMA_INVALID")

    post "/api/v1/custodied/contributions", params: "{}", headers: bearer("gal_nope")
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body["errors"].first["code"]).to eq("TOKEN_INVALID")
  end

  it "revokes a token through REVOKE_DELEGATION and refuses it afterwards (#3)" do
    post "/api/v1/assistants", params: { assistant: { name: "Claude", provider: "anthropic" } }.to_json, headers: headers
    token = response.parsed_body["token"]
    id = response.parsed_body["assistant"]["id"]

    delete "/api/v1/assistants/#{SecureRandom.uuid}", headers: bearer(token)
    expect(response.parsed_body["errors"].first["code"]).to eq("NOT_AUTHORIZED")

    delete "/api/v1/assistants/#{id}", headers: bearer(token)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["assistant"]["revoked"]).to be(true)
    record = AssistantToken.find(id)
    expect(record.delegation.reload).to be_revoked
    expect(Contribution.where(action_type: "REVOKE_DELEGATION", signer_key_id: record.principal.key_id).count).to eq(1)

    custodied_write(token, "CREATE_CLAIM", claim_payload("After revocation."))
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body["errors"].first["code"]).to eq("TOKEN_INVALID")
    expect(Assistants::Revoke.call(record)).to eq(record)
  end

  it "samples anonymous principals more often while scores stay byte-identical (#4)" do
    curator, = register_key(display_name: "Curator")
    location = create_location(curator, create_source(curator))
    evidence = create_evidence(curator, location)
    claim = create_claim(curator, "A claim with anonymous and named support.")
    seq_before = Contribution.maximum(:seq)

    anonymous, plaintext = Assistants::Connect.call(name: "Grok", provider: "xai")
    anon_link = Assistants::Write.call(anonymous, "LINK_EVIDENCE", { "evidence_item_id" => evidence.id, "claim_id" => claim.id, "direction" => "SUPPORT", "relevance_strength" => "DIRECT", "interpretive_steps" => 0 }).contribution
    schedule = AuditSchedule.find_by!(contribution_id: anon_link.id)
    expect(schedule.inputs).to include("principal_tier" => "ANONYMOUS")
    expect(BigDecimal(schedule.audit_probability)).to eq([ BigDecimal("0.10") * 5 * 2 * 3, BigDecimal(1) ].min)

    established = { "n" => "12.00", "mean" => "0.9000", "downstream_count" => 0, "outcome_is_unusual" => false }
    expect(Audits::Sample.probability_for(established.merge("principal_tier" => "PSEUDONYMOUS"))).to eq(BigDecimal("0.10"))
    expect(Audits::Sample.probability_for(established.merge("principal_tier" => "ANONYMOUS"))).to eq(BigDecimal("0.30"))

    model = Scoring::Registry.default_model
    anon_result = Scoring::Score.call(claim, Contribution.maximum(:seq), model)
    card = Cards::ClaimCard.call(claim, Contribution.maximum(:seq), model, anon_result)
    expect(card[:labels]).to include("Not yet independently audited; some evidence was recorded by an anonymous contributor.")

    # The same link from a named contributor: identical trace apart from ids.
    twin = create_claim(curator, "A claim with named support only.")
    link_evidence(curator, evidence, twin)
    named_result = Scoring::Score.call(twin, Contribution.maximum(:seq), model)
    expect(named_result.probability).to eq(anon_result.probability)
    expect(named_result.assessment_state).to eq(anon_result.assessment_state)
    expect(Cards::ClaimCard.call(twin, Contribution.maximum(:seq), model, named_result)[:labels]).to include("Not yet independently audited.")
    expect(AssistantToken.find_by_token(plaintext).writes_today).to eq(1)
    expect(seq_before).to be < anon_link.seq
  end

  it "enforces the daily cap and the per-token rate limit with plain messages (#5)" do
    record, token = Assistants::Connect.call(name: "Claude", provider: "anthropic", daily_cap: 2)
    custodied_write(token, "CREATE_CLAIM", claim_payload("One."))
    custodied_write(token, "CREATE_CLAIM", claim_payload("Two."))
    expect(response).to have_http_status(:created)
    custodied_write(token, "CREATE_CLAIM", claim_payload("Three."))
    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body["errors"].first).to include("code" => "DAILY_CAP")
    expect(response.parsed_body["errors"].first["detail"]).to include("try again tomorrow")
    expect(record.reload.writes_today).to eq(2)

    travel_to(Time.current.tomorrow.beginning_of_day + 1.hour) do
      custodied_write(token, "CREATE_CLAIM", claim_payload("Three, tomorrow."))
      expect(response).to have_http_status(:created)
    end

    with_rate_limiting do
      61.times { custodied_write(token, "CREATE_CLAIM", claim_payload("Burst.")) }
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body["errors"].first).to include("code" => "RATE_LIMITED")
    end
  end
end
