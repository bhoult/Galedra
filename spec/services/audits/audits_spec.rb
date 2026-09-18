require "rails_helper"

RSpec.describe "Audits and reputation (07 Phase 4)", type: :request do
  before { release_models }

  let(:curator) { register_key(display_name: "Curator").first }
  let(:reviewer) { register_reviewer.first }
  let(:model) { Scoring::Registry.default_model }

  def scored_graph
    source = create_source(curator, type: "DATASET", content: "Survey: 62% of 400 respondents reported higher productivity.")
    evidence = create_evidence(curator, create_location(curator, source), observation: "DATASET_RESULT")
    claim = create_claim(curator, "62% of respondents reported higher productivity.", type: "QUANTITATIVE")
    link = link_evidence(curator, evidence, claim, strength: "DIRECT")
    [ claim, link, evidence ]
  end

  it "SUBSTANTIVE_ERROR invalidates the target, lowers reputation, recomputes, and keeps history visible (#1)" do
    claim, link, = scored_graph
    before = Contribution.maximum(:seq)
    expect(Scoring::Score.call(claim, before, model)).to have_attributes(assessment_state: "SUPPORTED", provisional: true)

    audit = audit(reviewer, link, result: "SUBSTANTIVE_ERROR", note: "misread")
    invalidation = Contribution.where(action_type: "INVALIDATE").where("payload->>'audit_contribution_id' = ?", audit.contribution_id).first
    expect(invalidation.custody).to eq("SYSTEM")
    expect(link.reload.invalidated_seq).to eq(invalidation.seq)
    expect(link.contribution.reload.current_status).to eq("INVALIDATED")
    expect(Scoring::Score.call(claim, invalidation.seq, model).assessment_state).to eq("INSUFFICIENT_EVIDENCE")
    expect(Scoring::Score.call(claim, before, model).assessment_state).to eq("SUPPORTED")

    rep = Reputation::Calculate.call(contributor_id: Contributor.find_by!(key_id: curator.key_id).id, task_type: "MANUAL", domain: "general", snapshot_seq: Contribution.maximum(:seq))
    expect(rep).to include(alpha: "1.00", beta: "2.00", mean: "0.3333", n: "1.00", limited_history: true)

    get "/api/v1/contributions/#{link.contribution_id}"
    body = response.parsed_body
    expect(body["audits"].first).to include("result" => "SUBSTANTIVE_ERROR", "auditor_key_id" => reviewer.key_id, "task_type" => "MANUAL", "domain" => "general")
    expect(body["status_history"].map { |e| e["event"] }).to eq(%w[APPENDED ACCEPT AUDIT INVALIDATE])
    expect(body["audit_schedule"]).to include("policy_version" => "audit-policy-v0.1", "evaluated_at_seq" => link.contribution.seq)
  end

  it "CONFIRMED clears provisional, and a disagreeing re-audit restores the target with a new created_seq (#2)" do
    claim, link, = scored_graph
    expect(Scoring::Score.call(claim, Contribution.maximum(:seq), model).provisional).to be(true)
    confirmation = audit(reviewer, link)
    expect(Scoring::Score.call(claim, Contribution.maximum(:seq), model).provisional).to be(false)
    expect(Audits::Status.confirmed?(link.contribution_id, confirmation.created_seq - 1)).to be(false)

    other_reviewer = register_reviewer.first
    wrong = audit(other_reviewer, link, result: "FABRICATION", note: "wrong call")
    expect(link.reload).to be_invalidated
    gap_start = Contribution.maximum(:seq)
    expect(Scoring::Score.call(claim, gap_start, model).assessment_state).to eq("INSUFFICIENT_EVIDENCE")

    third = register_reviewer.first
    re_audit = audit(third, wrong, type: "RE_AUDIT", result: "SUBSTANTIVE_ERROR", note: "the evidence is real")
    expect(wrong.reload.invalidated_seq).to eq(re_audit.created_seq)
    expect(ReputationEvent.find_by(audit_id: wrong.id).invalidated_seq).to eq(re_audit.created_seq)
    expect(ReputationEvent.where(contributor_id: Contributor.find_by!(key_id: other_reviewer.key_id).id, task_type: "AUDIT").count).to eq(1)

    restoration = Contribution.where(action_type: "ACCEPT").where("payload->>'basis' = ?", "RESTORED_AFTER_RE_AUDIT").first
    expect(restoration.custody).to eq("SYSTEM")
    expect(link.contribution.reload.current_status).to eq("ACCEPTED")
    restored = EvidenceClaimLink.where(contribution_id: link.contribution_id).where.not(id: link.id).first
    expect(restored.created_seq).to eq(restoration.seq)
    expect(restored.accepted_seq).to eq(restoration.seq)
    expect(restored.relevance_strength).to eq("DIRECT")
    expect(link.reload.invalidated_seq).to be_present

    head = Contribution.maximum(:seq)
    expect(Scoring::Score.call(claim, head, model)).to have_attributes(assessment_state: "SUPPORTED", probability: "0.8581")
    expect(Scoring::Score.call(claim, gap_start, model).assessment_state).to eq("INSUFFICIENT_EVIDENCE")
    expect(Scoring::Score.call(claim, confirmation.created_seq, model).assessment_state).to eq("SUPPORTED")
    curator_rep = Reputation::Calculate.call(contributor_id: Contributor.find_by!(key_id: curator.key_id).id, task_type: "MANUAL", domain: "general", snapshot_seq: head)
    expect(curator_rep).to include(alpha: "2.00", beta: "1.00", mean: "0.6667")
  end

  it "reproduces reputation at any seq from events, rolls agents up to principals, and serves it (#3)" do
    principal_pair, agent_pair, agent, delegation = principal_with_agent
    source = create_source(curator)
    evidence = create_evidence(curator, create_location(curator, source))
    claim = create_claim(curator, "Agent-linked claim.")
    link = link_evidence(agent_pair, evidence, claim, delegation: delegation)
    accept(reviewer, link.contribution)
    first = audit(reviewer, link)
    seq_after_first = Contribution.maximum(:seq)
    audit(register_reviewer.first, link, result: "MINOR_ERROR", type: "SCHEMA_CHECK")

    principal = Contributor.find_by!(key_id: principal_pair.key_id)
    expect(Reputation::Calculate.call(contributor_id: agent.id, task_type: "MANUAL", domain: "general", snapshot_seq: seq_after_first)).to include(alpha: "2.00", beta: "1.00", n: "1.00")
    expect(Reputation::Calculate.call(contributor_id: agent.id, task_type: "MANUAL", domain: "general", snapshot_seq: Contribution.maximum(:seq))).to include(alpha: "2.70", beta: "1.30", mean: "0.6750", n: "2.00")
    expect(Reputation::Calculate.call(contributor_id: principal.id, task_type: "MANUAL", domain: "general", snapshot_seq: Contribution.maximum(:seq))).to include(alpha: "2.70", beta: "1.30")
    expect(Reputation::Calculate.call(contributor_id: agent.id, task_type: "MANUAL", domain: "general", snapshot_seq: first.created_seq - 1)).to include(alpha: "1.00", beta: "1.00", n: "0.00", limited_history: true)

    get "/api/v1/contributors/#{agent.id}/reputation", params: { snapshot_seq: seq_after_first }
    bucket = response.parsed_body["buckets"].first
    expect(bucket).to include("task_type" => "MANUAL", "domain" => "general", "mean" => "0.6667", "n" => "1.00", "limited_history" => true, "counts" => { "CONFIRMED" => 1 })
    expect(response.parsed_body["note"]).to match(/not authority/)
  end

  it "forbids auditing one's own or one's agents' work, and requires eligibility (#4)" do
    principal_pair, agent_pair, _, delegation = principal_with_agent
    source = create_source(curator)
    evidence = create_evidence(curator, create_location(curator, source))
    claim = create_claim(curator, "Claim.")
    own_link = link_evidence(curator, evidence, claim)
    agent_link = link_evidence(agent_pair, evidence, claim, delegation: delegation, note: "agent")
    accept(reviewer, agent_link.contribution)

    expect_rejected("NOT_AUTHORIZED") { audit(curator, own_link) }
    expect_rejected("NOT_AUTHORIZED") { audit(principal_pair, agent_link) }
    newcomer, = register_key
    expect_rejected("NOT_ELIGIBLE") { audit(newcomer, own_link) }
    expect_rejected("NOT_AUTHORIZED") { audit(Crypto::SystemKey.key_pair, own_link) }
    moderator, = register_moderator
    expect(audit(moderator, own_link)).to be_persisted
    expect(audit(reviewer, agent_link)).to be_persisted
    expect_rejected("SCHEMA_INVALID") { audit(reviewer, own_link, type: "RE_AUDIT") }
    expect_rejected("SCHEMA_INVALID") { audit(reviewer, own_link, result: "MAYBE") }
  end

  it "samples deterministically from the entry hash so anyone can recompute the decision (#5)" do
    _, link, = scored_graph
    schedule = AuditSchedule.find_by!(contribution_id: link.contribution_id)
    expect(schedule.inputs).to include("n" => "0.00", "mean" => "0.5000", "downstream_count" => 0, "outcome_is_unusual" => false)
    expect(schedule.audit_probability).to eq("1.0000")
    expect(schedule.sampled).to be(true)

    threshold = (BigDecimal(schedule.audit_probability) * Audits::Sample::TWO_256).floor
    recomputed = Digest::SHA256.hexdigest(link.contribution.entry_hash + schedule.policy_version).to_i(16) < threshold
    expect(recomputed).to eq(schedule.sampled)
    expect(Audits::Sample.probability_for("n" => "12.00", "mean" => "0.9000", "downstream_count" => 0, "outcome_is_unusual" => false)).to eq(BigDecimal("0.10"))
    expect(Audits::Sample.probability_for("n" => "12.00", "mean" => "0.9000", "downstream_count" => 5, "outcome_is_unusual" => true)).to eq(BigDecimal("0.40"))
    expect(Audits::Sample.sampled?("sha256:#{'0' * 64}", BigDecimal("0"))).to be(false)
    expect(Audits::Sample.sampled?("sha256:#{'f' * 64}", BigDecimal("1"))).to be(true)
  end

  it "anchors the schedule to the contribution's own seq: later audits, edges, and reputation change nothing (#6)" do
    claim, link, evidence = scored_graph
    schedule = AuditSchedule.find_by!(contribution_id: link.contribution_id)
    snapshot = schedule.attributes

    audit(reviewer, link)
    other = create_claim(curator, "Downstream.")
    create_edge(curator, claim, other, type: "SUPPORTS")
    second = link_evidence(curator, evidence, other, strength: "WEAK")
    expect(AuditSchedule.find_by!(contribution_id: link.contribution_id).attributes).to eq(snapshot)
    expect(AuditSchedule.find_by!(contribution_id: second.contribution_id).inputs).to include("n" => "1.00", "mean" => "0.6667", "downstream_count" => 0)

    before = Ledger::TableDigest.projections
    Ledger::Replay.call
    expect(Ledger::TableDigest.projections).to eq(before)
  end

  it "flags an unusual outcome and marks UNRESOLVED targets challenged until confirmed" do
    source = create_source(curator, content: "Two passages: one says yes; one says no.")
    location = create_location(curator, source)
    claim = create_claim(curator, "The text says yes.")
    con = create_evidence(curator, location, statement: "It says no.")
    contradiction = link_evidence(curator, con, claim, direction: "CONTRADICT", strength: "DIRECT")
    audit(reviewer, contradiction)
    pro = create_evidence(curator, location, statement: "It says yes.")
    support = link_evidence(curator, pro, claim, direction: "SUPPORT", strength: "DIRECT")
    expect(AuditSchedule.find_by!(contribution_id: support.contribution_id).inputs["outcome_is_unusual"]).to be(true)

    unresolved = audit(reviewer, support, result: "UNRESOLVED")
    expect(support.contribution.reload.current_status).to eq("CHALLENGED")
    expect(AuditSchedule.find_by!(contribution_id: support.contribution_id).rescheduled_by_seq).to eq(unresolved.created_seq)
    expect(Scoring::Score.call(claim, Contribution.maximum(:seq), model)).to have_attributes(support_groups: 0, contradict_groups: 1)
    expect(Scoring::Score.call(claim, unresolved.created_seq - 1, model).support_groups).to eq(1)

    audit(register_reviewer.first, support)
    expect(support.contribution.reload.current_status).to eq("ACCEPTED")
    expect(Scoring::Score.call(claim, Contribution.maximum(:seq), model).support_groups).to eq(1)
  end

  it "forces audits on a compromised key's contributions and excludes them from scoring until confirmed" do
    principal_pair, agent_pair, agent, delegation = principal_with_agent
    source = create_source(curator)
    evidence = create_evidence(curator, create_location(curator, source))
    claim = create_claim(curator, "Compromise test.")
    link = link_evidence(agent_pair, evidence, claim, delegation: delegation)
    accept(reviewer, link.contribution)
    expect(Scoring::Score.call(claim, Contribution.maximum(:seq), model).support_groups).to eq(1)

    revocation = append(action_type: "REVOKE_KEY", key_pair: principal_pair, payload: { "key_id" => agent.key_id, "compromised_since" => link.contribution.seq }).contribution
    expect(AuditSchedule.find_by!(contribution_id: link.contribution_id).forced_by_seq).to eq(revocation.seq)
    expect(Scoring::Score.call(claim, revocation.seq, model).support_groups).to eq(0)
    expect(Scoring::Score.call(claim, revocation.seq - 1, model).support_groups).to eq(1)

    audit(reviewer, link)
    expect(Scoring::Score.call(claim, Contribution.maximum(:seq), model).support_groups).to eq(1)
  end
end
