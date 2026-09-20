require "rails_helper"

RSpec.describe "Task leases over HTTP (04 §7)", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before { release_models }

  let(:headers) { { "CONTENT_TYPE" => "application/json" } }
  let(:curator) { register_key(display_name: "Curator").first }

  def signed(key_pair, payload: {}, delegation: nil, **options)
    Contributions::SignedRequest.build(protocol: "eir-lease-v1", payload: payload, key_pair: key_pair, delegation_id: delegation&.id, **options).to_json
  end

  def task_for(claim_text = "The passage states the figure.")
    location = create_location(curator, create_source(curator))
    create_task("EVIDENCE_VERIFICATION", create_claim(curator, claim_text), location: location)
  end

  it "leases, shows, and releases a task with signed requests, then refuses a second release" do
    _, agent_pair, _, delegation = principal_with_agent
    task = task_for

    post "/api/v1/tasks/next", params: signed(agent_pair, payload: { "types" => [ "EVIDENCE_VERIFICATION" ] }, delegation: delegation), headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["assignment"]).to include("task_id" => task.id, "status" => "LEASED")
    expect(response.parsed_body["packet"]["task_id"]).to eq(task.id)

    get "/api/v1/tasks/#{task.id}"
    expect(response.parsed_body["task"]).to include("status" => "LEASED", "results" => nil)
    expect(response.parsed_body["task"]["slots"]).to eq("required" => 1, "leased" => 1, "submitted" => 0)

    post "/api/v1/tasks/next", params: signed(agent_pair, delegation: delegation), headers: headers
    expect(response).to have_http_status(:no_content)

    post "/api/v1/tasks/#{task.id}/release", params: signed(agent_pair, delegation: delegation), headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["assignment"]["status"]).to eq("RELEASED")
    expect(task.reload.status).to eq("OPEN")

    post "/api/v1/tasks/#{task.id}/release", params: signed(agent_pair, delegation: delegation), headers: headers
    expect(response).to have_http_status(422)
    expect(response.parsed_body["errors"].first["code"]).to eq("LEASE_NOT_ACTIVE")

    post "/api/v1/tasks/#{task.id}/release", params: signed(curator), headers: headers
    expect(response.parsed_body["errors"].first["code"]).to eq("LEASE_MISSING")
  end

  it "rejects malformed, unknown, tampered, stale, and wrongly delegated lease requests" do
    _, agent_pair, agent, delegation = principal_with_agent
    task_for

    post "/api/v1/tasks/next", params: "{not json", headers: headers
    expect(response).to have_http_status(422)
    expect(response.parsed_body["errors"].first["code"]).to eq("SCHEMA_INVALID")

    post "/api/v1/tasks/next", params: { "protocol" => "eir-lease-v1" }.to_json, headers: headers
    expect(response.parsed_body["errors"].first["code"]).to eq("SCHEMA_INVALID")

    post "/api/v1/tasks/next", params: signed(key_pair, delegation: delegation), headers: headers
    expect(response.parsed_body["errors"].first["code"]).to eq("KEY_UNKNOWN")

    tampered = JSON.parse(signed(agent_pair, delegation: delegation)).merge("payload" => { "types" => [ "QUALIFIER_CHECK" ] })
    post "/api/v1/tasks/next", params: tampered.to_json, headers: headers
    expect(response.parsed_body["errors"].first["code"]).to eq("SIGNATURE_INVALID")

    post "/api/v1/tasks/next", params: signed(agent_pair, delegation: delegation, client_created_at: 1.hour.ago), headers: headers
    expect(response.parsed_body["errors"].first["code"]).to eq("SCHEMA_INVALID")
    expect(response.parsed_body["errors"].first["path"]).to eq("$.client_created_at")

    other_principal, = register_key
    other_agent_pair, other_agent = register_key(kind: Contributor::AGENT)
    other_delegation = delegate(other_principal, other_agent)
    post "/api/v1/tasks/next", params: signed(agent_pair, delegation: other_delegation), headers: headers
    expect(response.parsed_body["errors"].first["code"]).to eq("DELEGATION_INVALID")

    expired = delegate(other_principal, other_agent, valid_from: 2.days.ago, valid_until: 1.day.ago)
    post "/api/v1/tasks/next", params: signed(other_agent_pair, delegation: expired), headers: headers
    expect(response.parsed_body["errors"].first["code"]).to eq("DELEGATION_EXPIRED")

    expect_rejected("DELEGATION_REQUIRED") { Tasks::Lease.next(contributor: agent, delegation: nil) }
  end

  it "enforces the daily limit and expires stale leases" do
    principal_pair, = register_key
    agent_pair, agent = register_key(kind: Contributor::AGENT)
    delegation = delegate(principal_pair, agent, max_tasks_per_hour: 1)
    first = task_for("First claim.")
    task_for("Second claim.")

    assignment = lease(first, agent_pair, delegation: delegation)
    expect(assignment.task).to eq(first)
    expect_rejected("LEASE_LIMIT") { lease("EVIDENCE_VERIFICATION", agent_pair, delegation: delegation) }

    travel_to(assignment.lease_expires_at + 1.minute) do
      get "/api/v1/tasks/#{first.id}"
      expect(response.parsed_body["task"]["status"]).to eq("OPEN")
      expect(assignment.reload.status).to eq("EXPIRED")
    end
  end
end
