require "rails_helper"

# Stage 38. The score cache is keyed on the last seq at which anything bearing
# on a claim moved, so an unrelated write no longer invalidates it. The whole
# thing rests on that mark being complete: a member of the dependency set that
# can change a score without moving the mark would serve a stale score as
# current, silently and for as long as nobody wrote to the claim again.
#
# So every member is mutated here in turn, and the mark has to move. "Every
# member" is a claim this file has to keep earning: it once said so while never
# exercising an ACCEPT, an audit, or the evidence-item path, and four gaps
# shipped behind it. Where a
# spec would pass by accident if the mark simply never moved, the score is
# compared against the same claim scored with the cache emptied at the head,
# which is what the old code did.
RSpec.describe Scoring::Watermark do
  include GraphHelpers
  before { release_models }

  let(:model) { Scoring::Registry.default_model }

  def head = Contribution.maximum(:seq)
  def mark(claim) = Claim.find(claim.id).scored_inputs_seq

  # A claim with one piece of evidence behind it, and the pieces to hand.
  def scaffold
    pair, = register_key
    source = create_source(pair, title: "A report")
    location = create_location(pair, source)
    claim = create_claim(pair, "A claim with one source behind it.")
    evidence = create_evidence(pair, location)
    link = link_evidence(pair, evidence, claim)
    { pair: pair, source: source, location: location, claim: claim, evidence: evidence, link: link }
  end

  # What the old code did: no mark, cache emptied, scored at the seq asked for.
  def fresh_score(claim, seq)
    ClaimScore.where(claim_id: claim.id).delete_all
    Scoring::Registry.score(Scoring::BuildInput.call(Claim.find(claim.id), seq), model)
  end

  def expect_moved(claim, before, what)
    expect(mark(claim)).to be > before, "#{what} did not move the claim's watermark"
    # And the answer through the mark is the answer without one.
    through = Scoring::Score.call(Claim.find(claim.id), head, model)
    expect(through.trace.except("snapshot_seq")).to eq(fresh_score(claim, head).trace.except("snapshot_seq")),
                                                    "#{what}: scoring through the watermark disagreed with scoring at the head"
  end

  describe "the dependency set" do
    it "moves when evidence is linked, and when that link is invalidated" do
      s = scaffold
      before = mark(s[:claim])
      other = create_evidence(s[:pair], s[:location], statement: "A second reading of the passage.")
      link_evidence(s[:pair], other, s[:claim])
      expect_moved(s[:claim], before, "linking evidence")

      before = mark(s[:claim])
      invalidate(s[:pair], s[:link].contribution)
      expect_moved(s[:claim], before, "invalidating a link")
    end

    it "moves when the source behind its evidence is quarantined" do
      s = scaffold
      moderator, = register_moderator
      before = mark(s[:claim])
      quarantine(moderator, s[:source])
      expect_moved(s[:claim], before, "quarantining the source")
    end

    it "moves when the entry behind a link is audited" do
      s = scaffold
      auditor, = register_reviewer
      before = mark(s[:claim])
      audit(auditor, s[:link].contribution, result: "UNRESOLVED")
      expect_moved(s[:claim], before, "auditing a link")
    end

    it "moves when its evidence is assigned an independence group" do
      s = scaffold
      group = create_group(s[:pair])
      before = mark(s[:claim])
      assign_group(s[:pair], s[:evidence], group)
      expect_moved(s[:claim], before, "assigning an independence group")
    end

    it "moves when the claim is ruled not truth-evaluable" do
      s = scaffold
      before = mark(s[:claim])
      append(action_type: "SET_TRUTH_EVALUABLE", key_pair: s[:pair],
             payload: { "claim_id" => s[:claim].id, "truth_evaluable" => false, "not_evaluable_reason" => "NORMATIVE_OR_VALUE" })
      expect_moved(s[:claim], before, "setting truth evaluability")
    end

    # Provenance, not corroboration (Stage 35): what a claim is placed in decides
    # whether its own source counts as support, and a placement writes no row
    # that Scoring::Affected reads.
    it "moves when the claim is placed in an outline" do
      s = scaffold
      result = append(action_type: "CREATE_SECTION", key_pair: s[:pair],
                      payload: { "source_id" => s[:source].id, "sections" => [ { "heading" => "A part" } ] })
      section = Section.find(Ledger::Ids.derive(result.contribution.id, "section", 0))
      before = mark(s[:claim])
      append(action_type: "PLACE_CLAIM", key_pair: s[:pair],
             payload: { "claim_id" => s[:claim].id, "section_id" => section.id })
      expect_moved(s[:claim], before, "placing the claim in an outline")
    end

    # A review check raises review_coverage without writing anything that names
    # the claim: the task does, and the task is not a projection of the result.
    it "moves when a review check is answered on it" do
      s = scaffold
      worker, = register_reviewer
      task = create_task("QUALIFIER_CHECK", s[:claim])
      before = mark(s[:claim])
      submit_result(worker, task, outcome: "NONE_MATERIAL", ops: [])
      expect_moved(s[:claim], before, "answering a review check")
    end

    # An edge changes how many confirmations an audit of this claim's work needs
    # (Audits::Policy), so it can flip audit_confirmed on a link.
    it "moves when an edge is drawn from the claim" do
      s = scaffold
      other = create_claim(s[:pair], "Another claim, narrower than the first.")
      before = mark(s[:claim])
      create_edge(s[:pair], s[:claim], other)
      expect_moved(s[:claim], before, "drawing an edge")
    end

    # The accept, not just the write. Every epistemic entry is followed by an
    # ACCEPT, and it is the accept that makes a placement or a link count — the
    # code names accepting a placement as "what caught this", and no example
    # here exercised an ACCEPT at all until the review said so (2026-09-22).
    it "moves when the entry that makes something count is accepted" do
      s = scaffold
      # An agent without direct_work proposes; nothing counts until a principal
      # accepts, and it is the accept that changes the score.
      accepter, = register_reviewer(display_name: "Somebody else")
      _principal_pair, agent_pair, agent, delegation = principal_with_agent(permissions: {
        "allowed_task_types" => Tasks::Types::ALL, "domains" => Audits::Policy.domains, "direct_work" => false
      })
      expect(agent).to be_agent
      evidence = create_evidence(agent_pair, s[:location], statement: "A reading proposed, not yet accepted.", delegation: delegation)
      link = link_evidence(agent_pair, evidence, s[:claim], delegation: delegation)
      before = mark(s[:claim])

      # By somebody else: a principal may not accept its own work (Invariant 9).
      accept(accepter, link.contribution)
      expect_moved(s[:claim], before, "accepting a proposed link")
    end

    # An audit is not a projection row — `projection_rows` on an AUDIT
    # contribution is empty — so anything that reaches a claim only through an
    # audit row has to be resolved deliberately (code review, 2026-09-22).
    it "moves when an audit of its evidence is overturned by a later one" do
      s = scaffold
      auditor, = register_reviewer
      second, = register_reviewer(display_name: "Second reviewer")
      audit(auditor, s[:link].contribution, result: "CONFIRMED")
      before = mark(s[:claim])

      audit(second, s[:link].contribution, result: "UNRESOLVED")
      expect_moved(s[:claim], before, "overturning an audit")
    end

    # Two claims linked through one evidence item share an audit's fate, so what
    # confirms it for one confirms it for the other.
    it "moves a claim entangled through a shared evidence item" do
      s = scaffold
      neighbour = create_claim(s[:pair], "Another claim resting on the same evidence.")
      link_evidence(s[:pair], s[:evidence], neighbour)
      before = mark(neighbour)

      create_edge(s[:pair], s[:claim], create_claim(s[:pair], "Something the first claim narrows."))
      expect(mark(neighbour)).to be > before, "an edge changing an audit's requirements left the neighbour unmarked"
    end

    # A revocation can challenge any link the key signed, and there is no row to
    # find them by, so it marks everything. Rare, and the cost is one
    # recomputation a claim.
    it "moves every claim when a signing key is revoked" do
      s = scaffold
      other = scaffold
      revoker, = register_key
      before = [ mark(s[:claim]), mark(other[:claim]) ]
      append(action_type: "REVOKE_KEY", key_pair: revoker,
             payload: { "key_id" => revoker.key_id, "reason" => "ROTATION" })
      expect(mark(s[:claim])).to be > before.first
      expect(mark(other[:claim])).to be > before.last
    end
  end

  describe "what it buys" do
    it "leaves a claim's mark alone when the write was about something else, and serves the cached score" do
      s = scaffold
      first = Scoring::Score.call(Claim.find(s[:claim].id), head, model)
      before = mark(s[:claim])
      rows = ClaimScore.where(claim_id: s[:claim].id).count

      # A whole unrelated claim, with its own source and evidence: sixteen or so
      # appends, none of them touching the first claim.
      scaffold
      expect(mark(s[:claim])).to eq(before), "an unrelated write moved the claim's watermark"

      statements = 0
      counter = ->(*, payload) { statements += 1 if payload[:sql].to_s.include?("claim_scores") }
      again = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        Scoring::Score.call(Claim.find(s[:claim].id), head, model)
      end

      # One statement: the cache hit. Under the old keying this was a miss, a
      # full rebuild of the input and an insert, on every write to the node.
      expect(statements).to eq(1), "#{statements} statements against claim_scores for a claim nothing had touched"
      expect(again.trace_hash).to eq(first.trace_hash)
      expect(again.trace["snapshot_seq"]).to eq(before)
      expect(again.unchanged_since).to eq(before)
      expect(ClaimScore.where(claim_id: s[:claim].id).count).to eq(rows), "the cache grew for a claim nobody asked about"
    end

    it "never reports a snapshot_seq the score was not computed at" do
      s = scaffold
      at_write = head
      computed = Scoring::Score.call(Claim.find(s[:claim].id), at_write, model)
      scaffold # the head moves
      later = Scoring::Score.call(Claim.find(s[:claim].id), head, model)

      expect(later.trace["snapshot_seq"]).to eq(computed.trace["snapshot_seq"])
      expect(later.trace["snapshot_seq"]).to be <= at_write
      expect(later.unchanged_since).to eq(later.trace["snapshot_seq"])
      # And a question about the past is still answered at the seq it asked about.
      expect(Scoring::Score.call(Claim.find(s[:claim].id), at_write, model).unchanged_since).to be_nil
    end

    it "keys a whole page of claims on their own marks in one query" do
      claims = Array.new(4) { scaffold[:claim] }
      Scoring::Score.call_many(claims.map { |c| Claim.find(c.id) }, head, model)
      scaffold # an unrelated write

      statements = 0
      counter = ->(*, payload) { statements += 1 if payload[:sql].to_s.include?("claim_scores") }
      loaded = claims.map { |c| Claim.find(c.id) }
      results = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        Scoring::Score.call_many(loaded, head, model)
      end

      expect(results.size).to eq(claims.size)
      expect(statements).to eq(1), "#{statements} statements: a page of unchanged claims is one lookup and no insert"
      expect(results.values.map(&:unchanged_since)).to all(be_present)
    end
  end

  # A claim from before the stage, or one whose mark was cleared: no mark means
  # no information, and the old behaviour is the answer.
  it "falls back to the seq asked for when a claim has no mark" do
    s = scaffold
    Ledger::DatabaseRole.as_owner { Claim.where(id: s[:claim].id).update_all(scored_inputs_seq: nil) }
    result = Scoring::Score.call(Claim.find(s[:claim].id), head, model)

    expect(result.unchanged_since).to be_nil
    expect(result.trace["snapshot_seq"]).to eq(head)
    expect(ClaimScore.where(claim_id: s[:claim].id, snapshot_seq: head)).to be_any
  end
end
