require "rails_helper"

RSpec.describe Ledger::Replay do
  it "rebuilds identical projection rows, ids included, from the log" do
    principal, = register_key(display_name: "Alice")
    agent_pair, agent = register_key(kind: Contributor::AGENT, metadata: { "model" => "stub" })
    delegation = delegate(principal, agent)
    bad = append(action_type: "CREATE_SOURCE", key_pair: agent_pair, delegation_id: delegation.id, payload: { "t" => 1 }).contribution
    append(action_type: "REVOKE_KEY", key_pair: principal, payload: { "key_id" => agent.key_id, "compromised_since" => bad.seq })

    before = snapshot
    result = described_class.call
    expect(result.applied).to eq(Contribution.count)
    expect(snapshot).to eq(before)
    expect(bad.reload.current_status).to eq(Contribution::CHALLENGED)
  end

  it "refuses to replay a broken chain" do
    target = Contribution.in_order.last
    as_owner { Contribution.where(id: target.id).update_all(server_signature: "AAAA") }
    expect { described_class.call }.to raise_error(Ledger::ChainBroken)
  end

  def snapshot
    {
      contributors: Contributor.order(:key_id).map(&:attributes),
      delegations: AgentDelegation.order(:created_seq).map(&:attributes),
      statuses: Contribution.in_order.pluck(:seq, :current_status)
    }
  end
end
