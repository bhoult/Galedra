require "rails_helper"

RSpec.describe Ledger::Replay do
  it "rebuilds identical projection rows, ids included, from the log (07 Phase 2 #4)" do
    principal, = register_key(display_name: "Alice")
    reviewer, = register_key(display_name: "Reviewer")
    agent_pair, agent = register_key(kind: Contributor::AGENT, metadata: { "model" => "stub" })
    delegation = delegate(principal, agent)

    source = create_source(principal, title: "Survey", content: "62% of 400 respondents reported higher productivity.")
    location = create_location(principal, source, start: 0, finish: 20)
    broad = create_claim(principal, "62% of remote workers report higher productivity.", type: "QUANTITATIVE")
    narrow = create_claim(principal, "62% of 400 surveyed Acme customers reported higher productivity.", type: "QUANTITATIVE")
    evidence = create_evidence(principal, location, observation: "DATASET_RESULT")
    link = link_evidence(principal, evidence, broad, strength: "STRONG", steps: 1)
    create_edge(principal, narrow, broad, type: "NARROWS")
    group = create_group(principal)
    assign_group(principal, evidence, group)
    proposal = create_claim(agent_pair, "Agent proposal.", delegation: delegation)
    accept(reviewer, proposal.contribution)
    weaker = append(action_type: "SUPERSEDE_LINK", key_pair: principal,
                    payload: { "link_id" => link.id, "direction" => "SUPPORT", "relevance_strength" => "WEAK", "interpretive_steps" => 3 }).contribution
    append(action_type: "SET_TRUTH_EVALUABLE", key_pair: reviewer, payload: { "claim_id" => broad.id, "truth_evaluable" => false, "not_evaluable_reason" => "UNTESTABLE_CURRENT_METHODS" })
    invalidate(principal, weaker)
    bad = create_source(agent_pair, title: "bad", delegation: delegation).contribution
    append(action_type: "REVOKE_KEY", key_pair: principal, payload: { "key_id" => agent.key_id, "compromised_since" => bad.seq })

    before = Ledger::TableDigest.projections
    statuses_before = Contribution.in_order.pluck(:seq, :current_status)
    result = described_class.call
    expect(result.applied).to eq(Contribution.count)
    expect(Ledger::TableDigest.projections).to eq(before)
    expect(Contribution.in_order.pluck(:seq, :current_status)).to eq(statuses_before)
    expect(bad.reload.current_status).to eq(Contribution::CHALLENGED)
    expect(Ledger::TableDigest.projections.keys).to include("claims", "evidence_claim_links", "claim_merges", "contributors")
  end

  it "refuses to replay a broken chain" do
    target = Contribution.in_order.last
    as_owner { Contribution.where(id: target.id).update_all(server_signature: "AAAA") }
    expect { described_class.call }.to raise_error(Ledger::ChainBroken)
  end
end
