require "rails_helper"

RSpec.describe "Control contributions (07 Phase 1 #9)" do
  it "take effect on append without an ACCEPT" do
    principal, = register_key
    _, agent = register_key(kind: Contributor::AGENT)
    delegation = delegate(principal, agent, max_tasks_per_hour: 50)

    expect(delegation.principal.key_id).to eq(principal.key_id)
    expect(delegation.delegate).to eq(agent)
    expect(delegation.max_tasks_per_hour).to eq(50)
    expect(delegation.permissions["allowed_task_types"]).to eq(Tasks::Types::ALL)
    contribution = Contribution.find_by!(seq: delegation.created_seq)
    expect(contribution.current_status).to eq(Contribution::ACCEPTED)
    expect(contribution.action_type).to eq("DELEGATE")
    expect(delegation.delegation_signature).to eq(contribution.signature)
    expect(Contribution.where(action_type: "ACCEPT")).to be_empty
  end

  # The cap became hourly after delegations had already been signed with the old
  # key (REVIEW-NOTES M). Those contributions are in the log forever, so the
  # applier reads either name or replay stops reproducing them.
  it "applies a delegation signed before the field was renamed, and refuses one naming both" do
    principal, = register_key
    _, agent = register_key(kind: Contributor::AGENT)
    legacy = delegate(principal, agent, max_tasks_per_day: 50)
    expect(legacy.max_tasks_per_hour).to eq(50)

    expect_rejected("SCHEMA_INVALID") do
      delegate(principal, agent, max_tasks_per_day: 50, max_tasks_per_hour: 10)
    end
  end

  it "rejects and does not log an unauthorized control contribution" do
    alice, = register_key
    mallory, = register_key
    _, agent = register_key(kind: Contributor::AGENT)
    count = Contribution.count

    expect_rejected("NOT_AUTHORIZED") { append(action_type: "REVOKE_KEY", key_pair: mallory, payload: { "key_id" => alice.key_id }) }
    expect_rejected("NOT_AUTHORIZED") { append(action_type: "REVOKE_KEY", key_pair: mallory, payload: { "key_id" => Crypto::SystemKey.key_id }) }
    expect_rejected("DELEGATE_INVALID") { delegate(alice, Contributor.find_by!(key_id: mallory.key_id)) }
    expect_rejected("SCHEMA_INVALID") { delegate(alice, agent, valid_from: 1.day.from_now, valid_until: 1.day.ago) }
    expect(Contribution.count).to eq(count)
  end

  it "lets only the principal or delegate revoke a delegation" do
    principal, = register_key
    other, = register_key
    agent_pair, agent = register_key(kind: Contributor::AGENT)
    delegation = delegate(principal, agent)

    expect_rejected("NOT_AUTHORIZED") { append(action_type: "REVOKE_DELEGATION", key_pair: other, payload: { "delegation_id" => delegation.id }) }
    append(action_type: "REVOKE_DELEGATION", key_pair: agent_pair, delegation_id: delegation.id, payload: { "delegation_id" => delegation.id, "reason" => "done" })
    expect(delegation.reload).to be_revoked
    expect_rejected("ALREADY_REVOKED") { append(action_type: "REVOKE_DELEGATION", key_pair: principal, payload: { "delegation_id" => delegation.id }) }
  end
end
