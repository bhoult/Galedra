# frozen_string_literal: true

module Demo
  # Prints the golden tables with PASS/FAIL, the model comparison, the compact
  # answers, reputation, snapshot digests, URLs, and the replay check
  # (spec 07 Phase 7). Returns the number of failures.
  class Report
    GOLDEN = Rails.root.join("spec/fixtures/scoring_golden.json")
    FIELDS = %w[assessment_state probability stability review_coverage support_groups contradict_groups independence_unreviewed not_applicable_reason contested provisional].freeze
    REPUTATION = {
      "public-demo" => [
        [ "AgentBad", "EVIDENCE_VERIFICATION", "general", "1.00", "2.00", "0.3333", "1.00" ],
        [ "AgentVerifier", "CLAIM_EXTRACTION", "general", "2.00", "1.00", "0.6667", "1.00" ],
        [ "AgentVerifier", "OPPOSING_EVIDENCE_SEARCH", "general", "2.00", "1.00", "0.6667", "1.00" ],
        [ "AgentVerifier", "SOURCE_INDEPENDENCE_CHECK", "general", "2.00", "1.00", "0.6667", "1.00" ],
        [ "AgentVerifier", "QUALIFIER_CHECK", "general", "2.00", "1.00", "0.6667", "1.00" ],
        [ "Curator", "MANUAL", "general", "10.00", "1.00", "0.9091", "9.00" ]
      ],
      "watchers" => [
        [ "AgentVerifier", "EVIDENCE_VERIFICATION", "ancient_near_east", "2.00", "1.00", "0.6667", "1.00" ],
        [ "AgentBad", "EVIDENCE_VERIFICATION", "ancient_near_east", "1.00", "2.00", "0.3333", "1.00" ],
        [ "Mallory", "EVIDENCE_VERIFICATION", "ancient_near_east", "1.00", "2.00", "0.3333", "1.00" ],
        [ "AgentVerifier", "SOURCE_INDEPENDENCE_CHECK", "ancient_near_east", "2.00", "1.00", "0.6667", "1.00" ],
        [ "Curator", "MANUAL", "general", "6.00", "1.00", "0.8571", "5.00" ]
      ]
    }.freeze
    COMPARE_CLAIM = { "public-demo" => "C6", "watchers" => "C3" }.freeze

    def initialize(suite, result, out: $stdout, base_url: ENV.fetch("LEDGER_BASE_URL", "http://localhost:3000"))
      @suite = suite
      @r = result
      @out = out
      @base = base_url
      @failures = 0
    end

    def run
      golden_tables
      compare
      answers if @suite == "public-demo"
      reputation
      claim_identity if @suite == "public-demo"
      digests_and_replay
      urls
      @out.puts(@failures.zero? ? "ALL PASS" : "#{@failures} FAILURES")
      @failures
    end

    def check(label, ok, detail = nil)
      @failures += 1 unless ok
      @out.puts "#{ok ? 'PASS' : 'FAIL'} #{label}#{detail && !ok ? "\n     #{detail}" : ''}"
    end

    # The golden fixture names the models it covers; further releases are not the demo's concern.
    def golden
      @golden ||= JSON.parse(File.read(GOLDEN))
    end

    def models
      @models ||= golden["models"].values.map { |name| Scoring::Registry.find(name) }
    end

    def golden_tables
      cases = golden["cases"].select { |k| k["suite"] == @suite }
      models.each do |model|
        @out.puts "\n== #{@suite}: golden values under #{model.full_name}"
        cases.each do |kase|
          seq = @r.checkpoints.fetch(kase["checkpoint"])
          claim = @r.claims.fetch(kase["claim_handle"])
          result = Scoring::Score.call(claim, seq, model)
          got = FIELDS.to_h { |f| [ f, result.public_send(f) ] }
          expected = kase["expected"].fetch(model.full_name)
          check("#{kase['checkpoint']} #{kase['claim_handle']} #{got['assessment_state']} p=#{got['probability'].inspect} stab=#{got['stability'].inspect} cov=#{got['review_coverage']} sg=#{got['support_groups']} cg=#{got['contradict_groups']} unrev=#{got['independence_unreviewed']}#{' contested' if got['contested']}#{' provisional' if got['provisional']}",
                got == expected, "expected #{expected}")
        end
      end
    end

    def compare
      handle = COMPARE_CLAIM.fetch(@suite)
      claim = @r.claims.fetch(handle)
      seq = @r.checkpoints.fetch("S1")
      a, b = models
      ra = Scoring::Score.call(claim, seq, a)
      rb = Scoring::Score.call(claim, seq, b)
      diff = Scoring::Compare.call(ra, rb, config_a: a.config, config_b: b.config)
      @out.puts "\n== /compare for #{handle} at S1: #{diff['state_change'].inspect}; responsible config keys: #{diff['responsible_config_keys'].join(', ')}"
      check("#{handle} models disagree with scored_types named", diff["state_change"].present? && diff["responsible_config_keys"].include?("scored_types"))
    end

    def answers
      model = Scoring::Registry.default_model
      seq = @r.checkpoints.fetch("S5")
      @out.puts "\n== Compact answers at S5 (08 §9)"
      cards = %w[C2 C4].to_h { |handle| [ handle, Cards::ClaimCard.call(@r.claims.fetch(handle), seq, model) ] }
      cards.each do |handle, card|
        claim = @r.claims.fetch(handle)
        summary = Summaries::Generate.call(claim, seq, model)
        @out.puts "#{handle} — #{claim.canonical_text}"
        @out.puts "  #{card[:headline]}. #{summary[:sentences].map { |s| "#{s['text']} [#{s['cites'].map { |c| c.to_s[0, 8] }.join(', ')}]" }.join(' ')}"
      end
      check("C2 card: Unresolved, main issue is the qualifier", cards["C2"][:headline] == "Unresolved" && cards["C2"][:main_issue][:kind] == "QUALIFY_LINK")
      check("C4 card: Leans contradicted", cards["C4"][:headline] == "Leans contradicted")
      roll = Cards::SourceCard.call(@r.handles["SD"], seq, model)
      @out.puts "Memo summary: #{roll[:summary]}"
      check("memo roll-up covers 4 claims", roll[:cards].size == 4)
      sched = @r.handles["T2.schedule"]
      check("T2 audit sampling p=#{sched.audit_probability} sampled=#{sched.sampled} (n=#{sched.inputs['n']}, mean=#{sched.inputs['mean']})", sched.sampled && sched.audit_probability == "1.0000")
    end

    def reputation
      seq = @r.checkpoints.fetch("S5")
      @out.puts "\n== Reputation at S5"
      REPUTATION.fetch(@suite).each do |name, task_type, domain, alpha, beta, mean, n|
        contributor = Contributor.where(display_name: name).order(:created_seq).last
        rep = Reputation::Calculate.call(contributor_id: contributor.id, task_type: task_type, domain: domain, snapshot_seq: seq)
        got = [ rep[:alpha], rep[:beta], rep[:mean], rep[:n] ]
        check("#{name} #{task_type} × #{domain}: alpha #{rep[:alpha]} beta #{rep[:beta]} mean #{rep[:mean]} n #{rep[:n]}", got == [ alpha, beta, mean, n ], "expected #{[ alpha, beta, mean, n ]}")
      end
    end

    def claim_identity
      c2 = @r.claims["C2"]
      c3 = @r.claims["C3"]
      suggested = Claims::Duplicates.candidates(c2.canonical_text, exclude_id: c2.id).map(&:id)
      check("duplicate suggestions for C2 include C3 while no MERGE_CLAIMS exists", suggested.include?(c3.id) && ClaimMerge.where(from_claim_id: [ c2.id, c3.id ]).none?)
    end

    def digests_and_replay
      @out.puts "\n== Snapshot digests"
      before = @r.checkpoints.to_h { |name, seq| [ name, Snapshots::Digest.call(seq) ] }
      before.each { |name, digest| @out.puts "#{name} seq #{@r.checkpoints[name]} #{digest}" }
      verify = Ledger::Verify.call
      check("ledger:verify #{verify.status} (#{verify.checked} entries)", verify.ok?)
      Ledger::Replay.call
      after = @r.checkpoints.to_h { |name, seq| [ name, Snapshots::Digest.call(seq) ] }
      check("replay reproduces every snapshot digest", after == before, "before #{before} after #{after}")
    end

    def urls
      @out.puts "\n== URLs"
      @r.claims.sort.each { |handle, claim| @out.puts "#{handle}: #{@base}/claims/#{claim.id}" }
      @out.puts "memo source: #{@base}/sources/#{@r.handles['SD'].id}" if @r.handles["SD"]
      @out.puts "weaknesses: #{@base}/weaknesses · moderation: #{@base}/moderation · log: #{@base}/contributions"
    end
  end
end
