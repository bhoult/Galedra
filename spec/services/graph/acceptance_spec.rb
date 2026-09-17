require "rails_helper"

RSpec.describe "Acceptance (spec 02 §1.1a; 07 Phase 2 #6)" do
  it "keeps an agent's proposed claim unlinkable until a different principal accepts it" do
    principal_pair, agent_pair, _, delegation = principal_with_agent
    reviewer_pair, = register_key(display_name: "Reviewer")
    source = create_source(principal_pair)
    evidence = create_evidence(principal_pair, create_location(principal_pair, source))

    proposal = create_claim(agent_pair, "Proposed by an agent.", delegation: delegation)
    expect(proposal.accepted_seq).to be_nil
    expect(proposal.contribution.current_status).to eq(Contribution::PENDING)
    expect(Claim.counted_at(Contribution.maximum(:seq))).not_to include(proposal)

    expect_rejected("CLAIM_NOT_ACCEPTED") { link_evidence(principal_pair, evidence, proposal) }
    expect_rejected("NOT_AUTHORIZED") { accept(principal_pair, proposal.contribution) }
    expect_rejected("NOT_AUTHORIZED") { accept(agent_pair, proposal.contribution, delegation: delegation) }

    acceptance = accept(reviewer_pair, proposal.contribution)
    expect(proposal.reload.accepted_seq).to eq(acceptance.seq)
    expect(proposal.contribution.reload.current_status).to eq(Contribution::ACCEPTED)
    expect(link_evidence(principal_pair, evidence, proposal)).to be_persisted
    another_reviewer, = register_key
    expect_rejected("ALREADY_ACCEPTED") { accept(another_reviewer, proposal.contribution) }
  end

  it "lets an agent accept only when its delegation lists ACCEPT" do
    author_pair, = register_key
    _, agent_pair, _, delegation = principal_with_agent(permissions: { "allowed_task_types" => [], "domains" => [], "allowed_actions" => [ "ACCEPT" ] })
    _, plain_agent_pair, _, plain_delegation = principal_with_agent
    claim = create_claim(author_pair, "Human claim.")
    proposal_by_plain = create_claim(plain_agent_pair, "Plain agent proposal.", delegation: plain_delegation)

    expect_rejected("NOT_AUTHORIZED") { accept(plain_agent_pair, proposal_by_plain.contribution, delegation: plain_delegation) }
    expect(accept(agent_pair, proposal_by_plain.contribution, delegation: delegation)).to be_persisted
    expect_rejected("ALREADY_ACCEPTED") { accept(agent_pair, claim.contribution, delegation: delegation) }
  end

  it "never auto-accepts SET_TRUTH_EVALUABLE and applies it only once a different principal accepts" do
    author_pair, = register_key
    reviewer_pair, = register_key
    claim = create_claim(author_pair, "Consciousness survives death.", type: "HISTORICAL")
    expect(claim.truth_evaluable).to be(true)

    setting = append(action_type: "SET_TRUTH_EVALUABLE", key_pair: author_pair,
                     payload: { "claim_id" => claim.id, "truth_evaluable" => false, "not_evaluable_reason" => "UNTESTABLE_CURRENT_METHODS" })
    expect(setting.acceptance).to be_nil
    expect(claim.reload.truth_evaluable).to be(true)

    accepted = accept(reviewer_pair, setting.contribution)
    expect(claim.reload.truth_evaluable).to be(false)
    expect(claim.not_evaluable_reason).to eq("UNTESTABLE_CURRENT_METHODS")
    expect(claim.evaluability_at(accepted.seq - 1)).to eq([ true, nil ])
    expect(claim.evaluability_at(accepted.seq)).to eq([ false, "UNTESTABLE_CURRENT_METHODS" ])

    invalidate(author_pair, setting.contribution, reason: "reconsidered")
    expect(claim.reload.truth_evaluable).to be(true)
  end

  it "treats a supersession of another principal's link as a proposal" do
    alice_pair, = register_key
    bob_pair, = register_key
    source = create_source(alice_pair)
    evidence = create_evidence(alice_pair, create_location(alice_pair, source))
    claim = create_claim(alice_pair, "A claim.")
    link = link_evidence(alice_pair, evidence, claim, strength: "STRONG", steps: 1)
    head = Contribution.maximum(:seq)

    revision = append(action_type: "SUPERSEDE_LINK", key_pair: bob_pair,
                      payload: { "link_id" => link.id, "direction" => "SUPPORT", "relevance_strength" => "WEAK", "interpretive_steps" => 3, "reason" => "customer-only sample" })
    expect(revision.acceptance).to be_nil
    expect(link.effective_at?(Contribution.maximum(:seq))).to be(true)

    expect_rejected("NOT_AUTHORIZED") { accept(bob_pair, revision.contribution) }
    accepted = accept(alice_pair, revision.contribution)
    new_link = EvidenceClaimLink.find(Ledger::Ids.derive(revision.contribution.id, "link"))
    expect(new_link.supersedes_link_id).to eq(link.id)
    expect(link.effective_at?(accepted.seq)).to be(false)
    expect(link.effective_at?(head)).to be(true)
    expect(new_link.effective_at?(accepted.seq)).to be(true)
    expect_rejected("LINK_SUPERSEDED") { append(action_type: "SUPERSEDE_LINK", key_pair: alice_pair, payload: { "link_id" => link.id, "direction" => "SUPPORT", "relevance_strength" => "WEAK", "interpretive_steps" => 0 }) }

    # Bob's revision belongs to Bob even though Alice accepted it; superseding it is again a proposal.
    theirs = append(action_type: "SUPERSEDE_LINK", key_pair: alice_pair, payload: { "link_id" => new_link.id, "direction" => "SUPPORT", "relevance_strength" => "MODERATE", "interpretive_steps" => 1 })
    expect(theirs.acceptance).to be_nil

    own_link = link_evidence(alice_pair, evidence, claim, direction: "QUALIFY", strength: "DIRECT")
    own = append(action_type: "SUPERSEDE_LINK", key_pair: alice_pair, payload: { "link_id" => own_link.id, "direction" => "QUALIFY", "relevance_strength" => "MODERATE", "interpretive_steps" => 1 })
    expect(own.acceptance).to be_present
  end

  it "lets only the principal or the system invalidate, and closes every row the contribution created" do
    alice_pair, = register_key
    bob_pair, = register_key
    principal_pair, agent_pair, _, delegation = principal_with_agent
    claim = create_claim(alice_pair, "Alice's claim.")
    expect_rejected("NOT_AUTHORIZED") { invalidate(bob_pair, claim.contribution) }

    proposal = create_source(agent_pair, title: "agent source", delegation: delegation)
    invalidation = invalidate(principal_pair, proposal.contribution, reason: "agent error")
    expect(proposal.reload.invalidated_seq).to eq(invalidation.seq)
    expect(proposal.contribution.reload.current_status).to eq(Contribution::INVALIDATED)
    expect_rejected("ALREADY_INVALIDATED") { invalidate(principal_pair, proposal.contribution) }

    retired = invalidate(alice_pair, claim.contribution)
    expect(claim.reload.status).to eq("RETIRED")
    expect(claim.status_at(retired.seq - 1)).to eq("ACTIVE")
    expect(claim.status_at(retired.seq)).to eq("RETIRED")
    expect_rejected("TARGET_INVALIDATED") { link_evidence(alice_pair, create_evidence(alice_pair, create_location(alice_pair, create_source(alice_pair))), claim) }
  end
end
