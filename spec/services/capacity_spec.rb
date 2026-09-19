require "rails_helper"

RSpec.describe "Capacity: batched scoring, score-cache retention, and a bounded report (Stage 26)" do
  include LedgerHelpers
  include GraphHelpers
  before { release_models }

  def graph(count)
    pair, = register_key
    source = create_source(pair)
    location = create_location(pair, source)
    claims = Array.new(count) { |i| create_claim(pair, "Claim number #{i} of the corpus.") }
    claims.each_with_index do |c, i|
      link_evidence(pair, create_evidence(pair, location, statement: "The passage bears on claim #{i}."), c,
                    direction: i.even? ? "SUPPORT" : "CONTRADICT")
    end
    [ pair, claims ]
  end

  it "scores a set in one cache query and returns byte-identical traces to scoring one at a time (#1)" do
    _pair, claims = graph(6)
    seq = Contribution.maximum(:seq)
    model = Scoring::Registry.default_model

    one_at_a_time = claims.to_h { |c| [ c.id, Scoring::Score.call(c, seq, model) ] }
    ClaimScore.delete_all

    # Only the cache traffic: building a claim's input still costs its own
    # queries, and that is the next thing down, not what this change touched.
    cache_queries = 0
    counter = ->(*, payload) { cache_queries += 1 if payload[:sql].to_s.include?("claim_scores") }
    batched = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      Scoring::Score.call_many(claims, seq, model)
    end

    # The number, the state and the trace are what Invariant 4 protects. Where
    # the answer came from is not allowed to change any of them.
    claims.each do |c|
      expect(batched[c.id].trace).to eq(one_at_a_time[c.id].trace)
      expect(batched[c.id].trace_hash).to eq(one_at_a_time[c.id].trace_hash)
      expect(batched[c.id].assessment_state).to eq(one_at_a_time[c.id].assessment_state)
    end

    # Six claims used to mean six cache lookups and six inserts. Now it is one
    # of each, whatever the corpus: the count no longer grows with it.
    expect(cache_queries).to eq(2), "expected one lookup and one insert, got #{cache_queries} statements"
    expect(ClaimScore.where(snapshot_seq: seq).count).to eq(claims.size)

    # A second call is served from the cache and writes nothing.
    expect { Scoring::Score.call_many(claims, seq, model) }.not_to change(ClaimScore, :count)
  end

  it "prunes the score cache to the head, the pinned snapshots, and recent work, and loses nothing (#2)" do
    _pair, claims = graph(3)
    model = Scoring::Registry.default_model
    early = Contribution.maximum(:seq)
    Scoring::Score.call_many(claims, early, model)
    pinned = Snapshots::Create.call(seq: early, label: "pinned for retention")

    create_claim(register_key.first, "One more, so the head moves past the pinned snapshot.")
    head = Contribution.maximum(:seq)
    head_results = Scoring::Score.call_many(claims, head, model)
    middle = (early + 1)
    Scoring::Score.call_many(claims, middle, model) if middle < head
    ClaimScore.where.not(snapshot_seq: [ early, head ]).update_all(computed_at: 30.days.ago)

    expect(Scoring::Prune.call(keep_days: 7, dry_run: true).deleted).to eq(ClaimScore.where.not(snapshot_seq: [ early, head ]).count)
    result = Scoring::Prune.call(keep_days: 7)

    expect(ClaimScore.where(snapshot_seq: head)).to be_any, "the head must survive"
    expect(ClaimScore.where(snapshot_seq: pinned.seq)).to be_any, "a pinned snapshot must survive"
    expect(ClaimScore.where.not(snapshot_seq: [ early, head ])).to be_empty
    expect(result.deleted).to be_positive

    # The property that makes a cache safe to throw away: it comes back the same.
    ClaimScore.where(snapshot_seq: head).delete_all
    Scoring::Score.call_many(claims, head, model).each do |id, r|
      expect(r.trace).to eq(head_results[id].trace)
      expect(r.trace_hash).to eq(head_results[id].trace_hash)
    end

    # Idempotent: a second run has nothing left to do.
    expect(Scoring::Prune.call(keep_days: 7).deleted).to eq(0)
  end

  it "caps each weakness list, says how many there really are, and pages without recomputing (#3)" do
    _pair, claims = graph(5)
    seq = Contribution.maximum(:seq)

    full = Weaknesses::Report.call(seq, kind: "contested", limit: 100)
    total = full[:totals]["contested"]
    expect(full[:max_entries]).to eq(Weaknesses::Report::MAX_ENTRIES)

    first = Weaknesses::Report.call(seq, kind: "contested", limit: 2, offset: 0)
    second = Weaknesses::Report.call(seq, kind: "contested", limit: 2, offset: 2)
    expect(first[:totals]["contested"]).to eq(total)
    expect(first[:offset]).to eq(0)
    expect(second[:offset]).to eq(2)
    expect(first[:lists]["contested"] & second[:lists]["contested"]).to be_empty

    # Paging must not buy another whole-graph scan: the cache is keyed on the
    # snapshot and the model, not on the page anyone asked for. The suite runs
    # with a null cache store, so this needs a real one to mean anything.
    store = ActiveSupport::Cache::MemoryStore.new
    original = Rails.cache
    Rails.cache = store
    Weaknesses::Report.call(seq, kind: "contested", limit: 2, offset: 0)
    expect(Scoring::Score).not_to receive(:call_many)
    paged = Weaknesses::Report.call(seq, kind: "contested", limit: 2, offset: 2)
    expect(paged[:totals]["contested"]).to eq(total)
  ensure
    Rails.cache = original if original
  end
end
