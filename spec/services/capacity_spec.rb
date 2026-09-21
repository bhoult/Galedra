require "rails_helper"

RSpec.describe "Capacity: batched scoring, score-cache retention, and a bounded report (Stage 26)" do
  include LedgerHelpers
  include GraphHelpers
  before { release_models }

  # A \r frame is invisible off a terminal: a 100k seed left 79 bytes in
  # `docker logs` after 21 hours (docs/profiler/2026-09-20-seed-write-path-decay.md).
  it "reports seed progress in whole lines when nothing is a terminal" do
    out = StringIO.new
    seed = Bench::Seed.new(claims: 10, out: out)
    seed.send(:report, 4, 0, seed.send(:clock) - 2)
    seed.send(:report, 8, 0, seed.send(:clock) - 4)

    lines = out.string.lines
    expect(lines.size).to eq(2), "each batch gets its own line, not a redraw of one"
    expect(out.string).not_to include("\r"), "a carriage return reaches no log"
    expect(lines.last).to match(/\A\d{4}-\d{2}-\d{2}T[\d:]+Z\s+8\/10 claims/), "with the time, because the reader is a log"
  end

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

  # Scoring::Pass batches the per-link lookups across a whole set: quarantines,
  # audits by target, and key-compromise windows. The property that matters is
  # that it changes how often a question is asked and never the answer, so this
  # builds a graph where all three actually fire — an audited link, a quarantined
  # source, and several claims — and compares traces byte for byte.
  it "batches the per-link lookups across a set without moving a trace" do
    author, = register_key
    reviewer = register_reviewer.first
    moderator = register_moderator.first
    source = create_source(author, content: "Survey: 62% of 400 respondents reported higher productivity.")
    location = create_location(author, source)
    claims = Array.new(4) { |i| create_claim(author, "Claim #{i}: 62% of respondents reported higher productivity.", type: "QUANTITATIVE") }
    claims.each_with_index do |c, i|
      evidence = create_evidence(author, location, statement: "The passage bears on claim #{i}.")
      link = link_evidence(author, evidence, c, direction: i.even? ? "SUPPORT" : "CONTRADICT")
      audit(reviewer, link) if i < 2
    end
    quarantined = create_source(author, title: "Withheld", content: "Another passage entirely.")
    quarantined_claim = create_claim(author, "A claim resting on a withheld source.", type: "QUANTITATIVE")
    link_evidence(author, create_evidence(author, create_location(author, quarantined), statement: "It says so."), quarantined_claim)
    quarantine(moderator, quarantined)
    all = claims + [ quarantined_claim ]

    seq = Contribution.maximum(:seq)
    model = Scoring::Registry.default_model
    one_at_a_time = all.to_h { |c| [ c.id, Scoring::Score.call(c, seq, model) ] }
    ClaimScore.delete_all

    counts = Hash.new(0)
    counter = lambda do |*, payload|
      sql = payload[:sql].to_s
      counts[:audits] += 1 if sql.include?('"audits"')
      counts[:quarantines] += 1 if sql.include?('"quarantines"')
      counts[:revocations] += 1 if sql.include?("REVOKE_KEY")
    end
    batched = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      Scoring::Score.call_many(all, seq, model)
    end

    # Invariant 4 is the point: the number, the state and the trace cannot move
    # because of where the answer came from.
    all.each do |c|
      expect(batched[c.id].trace).to eq(one_at_a_time[c.id].trace), "trace moved for #{c.id}"
      expect(batched[c.id].trace_hash).to eq(one_at_a_time[c.id].trace_hash)
      expect(batched[c.id].assessment_state).to eq(one_at_a_time[c.id].assessment_state)
      expect(batched[c.id].probability).to eq(one_at_a_time[c.id].probability)
    end

    # Bounded by the pass rather than by the number of links: one load each, not
    # one per link per kind.
    expect(counts[:quarantines]).to be <= 1
    expect(counts[:revocations]).to be <= 1
    expect(counts[:audits]).to be <= 2, "one grouped load for the set, not one per link"
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
    # One row per claim, keyed on that claim's watermark rather than on the seq
    # anyone asked for (Stage 38); at this corpus every claim was last touched
    # at or before the head.
    expect(ClaimScore.count).to eq(claims.size)
    claims.each do |c|
      mark = Claim.find(c.id).scored_inputs_seq
      expect(ClaimScore.where(claim_id: c.id, snapshot_seq: mark)).to be_any, "no row at claim #{c.id}'s watermark #{mark}"
    end

    # A second call is served from the cache and writes nothing.
    expect { Scoring::Score.call_many(claims, seq, model) }.not_to change(ClaimScore, :count)
  end

  it "prunes the score cache to what is current, the pinned snapshots, and recent work, and loses nothing (#2)" do
    _pair, claims = graph(3)
    model = Scoring::Registry.default_model
    early = Contribution.maximum(:seq)
    Scoring::Score.call_many(claims, early, model)
    pinned = Snapshots::Create.call(seq: early, label: "pinned for retention")

    create_claim(register_key.first, "One more, so the head moves past the pinned snapshot.")
    head = Contribution.maximum(:seq)
    head_results = Scoring::Score.call_many(claims, head, model)
    current = ClaimScore.all.to_a
    # Stage 38: reading at the new head reused what was already cached, because
    # nothing bearing on these claims moved. There is nothing to prune yet.
    expect(Scoring::Prune.call(keep_days: 7, dry_run: true).deleted).to eq(0)

    # Rows from seqs nobody keys on any more: the old behaviour, one per read.
    stale = current.map do |row|
      ClaimScore.create!(row.attributes.merge("id" => SecureRandom.uuid_v7, "snapshot_seq" => row.snapshot_seq - 1,
                                              "computed_at" => 30.days.ago))
    end

    expect(Scoring::Prune.call(keep_days: 7, dry_run: true).deleted).to eq(stale.size)
    result = Scoring::Prune.call(keep_days: 7)

    claims.each do |c|
      mark = Claim.find(c.id).scored_inputs_seq
      expect(ClaimScore.where(claim_id: c.id, snapshot_seq: mark)).to be_any, "a claim's current score must survive"
    end
    expect(ClaimScore.where(snapshot_seq: pinned.seq)).to be_any, "a pinned snapshot must survive"
    expect(ClaimScore.where(id: stale.map(&:id))).to be_empty
    expect(result.deleted).to eq(stale.size)

    # The property that makes a cache safe to throw away: it comes back the same.
    ClaimScore.where(id: current.map(&:id)).delete_all
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
