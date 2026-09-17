require "rails_helper"

RSpec.describe "Revocation (07 Phase 1 #4, #5)" do
  it "stops a revoked key from appending while its history still verifies" do
    pair, contributor = register_key
    earlier = append(action_type: "CREATE_CLAIM", key_pair: pair, payload: { "canonical_text" => "before" }).contribution
    revocation = append(action_type: "REVOKE_KEY", key_pair: pair, payload: { "key_id" => pair.key_id, "reason" => "retired" }).contribution

    expect(contributor.reload.revoked_seq).to eq(revocation.seq)
    expect_rejected("KEY_REVOKED") { append(action_type: "CREATE_CLAIM", key_pair: pair, payload: { "canonical_text" => "after" }) }

    expect(Ledger::Verify.entry(earlier)).to include(client_signature_ok: true, chain_ok: true)
    expect(Ledger::Verify.call.status).to eq(Ledger::Verify::CHAIN_VERIFIED)
  end

  it "lets a principal revoke its agent and marks contributions since the compromise CHALLENGED" do
    principal, = register_key
    agent_pair, agent = register_key(kind: Contributor::AGENT)
    delegation = delegate(principal, agent)
    good = append(action_type: "CREATE_SOURCE", key_pair: agent_pair, delegation_id: delegation.id, payload: { "title" => "good" }).contribution
    bad = append(action_type: "CREATE_SOURCE", key_pair: agent_pair, delegation_id: delegation.id, payload: { "title" => "bad" }).contribution

    append(action_type: "REVOKE_KEY", key_pair: principal, payload: { "key_id" => agent.key_id, "compromised_since" => bad.seq })

    expect(agent.reload).to be_revoked
    expect(good.reload.current_status).to eq(Contribution::PENDING)
    expect(bad.reload.current_status).to eq(Contribution::CHALLENGED)
    expect_rejected("KEY_REVOKED") { append(action_type: "CREATE_SOURCE", key_pair: agent_pair, delegation_id: delegation.id, payload: {}) }
  end

  it "requires agents to act under a live delegation" do
    principal, = register_key
    agent_pair, agent = register_key(kind: Contributor::AGENT)
    expect_rejected("DELEGATION_REQUIRED") { append(action_type: "CREATE_SOURCE", key_pair: agent_pair, payload: {}) }

    delegation = delegate(principal, agent)
    expect(append(action_type: "CREATE_SOURCE", key_pair: agent_pair, delegation_id: delegation.id, payload: {}).created).to be(true)

    append(action_type: "REVOKE_DELEGATION", key_pair: principal, payload: { "delegation_id" => delegation.id })
    expect_rejected("DELEGATION_REVOKED") { append(action_type: "CREATE_SOURCE", key_pair: agent_pair, delegation_id: delegation.id, payload: { "n" => 2 }) }

    expired = delegate(principal, agent, valid_from: 2.days.ago, valid_until: 1.day.ago)
    expect_rejected("DELEGATION_EXPIRED") { append(action_type: "CREATE_SOURCE", key_pair: agent_pair, delegation_id: expired.id, payload: { "n" => 3 }) }

    expect_rejected("DELEGATION_INVALID") { append(action_type: "CREATE_SOURCE", key_pair: principal, delegation_id: delegation.id, payload: {}) }
  end
end
