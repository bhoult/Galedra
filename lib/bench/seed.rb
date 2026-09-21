# frozen_string_literal: true

module Bench
  # A corpus built through the real write path (Stage 26). Not fixtures: every
  # row here is a signed contribution that went through Ledger::Append, so the
  # timings taken against it mean what they say. Development and test only.
  #
  # The append lock is per transaction, so bulk seeding wraps batches to keep a
  # large corpus achievable; the honest unbatched rate is measured separately on
  # a small sample and reported, because that is the number capacity planning
  # needs (a live node appends one contribution per transaction).
  class Seed
    TYPES = %w[OBSERVATIONAL QUANTITATIVE HISTORICAL TEXTUAL CAUSAL COMPARATIVE NORMATIVE FORECAST].freeze
    DIRECTIONS = %w[SUPPORT SUPPORT SUPPORT CONTRADICT QUALIFY].freeze
    SAMPLE = 25

    def self.call(...) = new(...).call

    def initialize(claims:, reset: false, batch: 250, seed: 20_260_919, out: $stdout)
      raise ArgumentError, "bench:seed runs in development and test only" unless Rails.env.development? || Rails.env.test?

      @claims = Integer(claims)
      @reset = reset
      @batch = Integer(batch)
      @rng = Random.new(Integer(seed))
      @out = out
    end

    def call
      prepare!
      h = Demo::Helpers.new
      authors = 4.times.map { |i| h.register_server_user("bench#{i}@galedra.invalid", display_name: "Bench author #{i}").last }
      auditor = h.register_server_user("benchaudit@galedra.invalid", display_name: "Bench auditor", identity_tier: "ESTABLISHED").last

      rate = measure_unbatched(h, authors.first)
      @out.puts "unbatched append rate: #{rate.round(1)}/s (#{(1000 / rate).round(1)} ms each) over #{SAMPLE} appends"

      before = Contribution.count
      made = 0
      started = clock
      # Held still for the same reason a measurement is (Bench::Isolation): a
      # million appends through development's verbose query logs write gigabytes
      # nobody reads, and the writing is a large share of the time. Measured
      # 2026-09-21: 56 MB of log in the first minutes of a 100,000-claim run.
      Isolation.call do
        while made < @claims
          Contribution.transaction do
            @batch.times do
              break if made >= @claims

              made += investigation(h, authors[@rng.rand(authors.size)], auditor)
            end
          end
          report(made, before, started)
        end
      end
      appended = Contribution.count - before
      elapsed = clock - started
      @out.puts "seeded #{made} claims in #{appended} contributions, #{elapsed.round(1)}s " \
                "(#{(appended / elapsed).round(1)}/s batched, #{(appended.to_f / made).round(1)} contributions per claim)"
      if Rails.env.test?
        @out.puts "NOTE: this corpus is in the test database, where the suite expects a clean log. " \
                  "Before running rspec: bin/rails db:drop db:create db:schema:load (RAILS_ENV=test)."
      end
      { claims: made, contributions: appended, seconds: elapsed, unbatched_rate: rate }
    end

    private

    def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    def prepare!
      # Stage 17 would queue a fetch for every source held by reference.
      ENV["LEDGER_RETRIEVAL"] = "off"
      if Contribution.where.not(seq: 0).any?
        raise "the log already holds contributions; pass reset: true" unless @reset && Rails.env.local?

        @out.puts "resetting the log"
        tables = ActiveRecord::Base.connection.tables - %w[schema_migrations ar_internal_metadata]
        Ledger::DatabaseRole.as_owner { ActiveRecord::Base.connection.truncate_tables(*tables) }
      end
      # Also on a database that was merely empty: scoring needs a released model.
      Ledger::Genesis.ensure!
      Ledger::ReleaseModels.call
    end

    # One recorded investigation: a source held by reference, its quoted
    # passages, the claims they bear on, and the links between them.
    def investigation(h, author, auditor)
      n = 1 + @rng.rand(3)
      source = reference_source(h, author)
      locations = (1 + @rng.rand(3)).times.map { |i| quote(h, author, source, i) }
      claims = n.times.map { |i| h.create_claim(author, sentence(i), type: TYPES[@rng.rand(TYPES.size)]) }
      claims.each do |claim|
        tag(h, author, claim) if @rng.rand(3).zero?
        (1 + @rng.rand(2)).times do
          location = locations[@rng.rand(locations.size)]
          evidence = h.create_evidence(author, location, statement: "The passage bears on this claim.")
          h.link(author, evidence, claim, direction: DIRECTIONS[@rng.rand(DIRECTIONS.size)], steps: @rng.rand(3))
        end
        h.audit(auditor, claim.contribution, result: "CONFIRMED") if @rng.rand(12).zero?
      end
      claims.size
    end

    def reference_source(h, author)
      i = @rng.rand(1_000_000)
      payload = { "source_type" => %w[WEBSITE SECONDARY_TEXT PRIMARY_TEXT].sample(random: @rng),
                  "title" => "Bench source #{i}", "canonical_uri" => "https://bench.invalid/#{i}",
                  "retrieved_at" => Time.now.utc.iso8601 }
      h.row_for(h.server_append(author, "CREATE_SOURCE", payload), "source", Source)
    end

    def quote(h, author, source, i)
      text = "Quoted passage #{i} of source #{source.id[0, 8]}: #{sentence(i)}"
      payload = { "source_id" => source.id, "locator_type" => "QUOTE", "locator" => { "page" => i + 1 },
                  "excerpt" => text, "excerpt_hash" => Crypto::Hashing.bytes(text) }
      h.row_for(h.server_append(author, "CREATE_SOURCE_LOCATION", payload), "location", SourceLocation)
    end

    def tag(h, author, claim)
      h.server_append(author, "TAG_CLAIM", { "claim_id" => claim.id, "topics" => [ Topics.all.sample(random: @rng) ] })
    end

    SUBJECTS = [ "remote work", "clean electricity", "the survey", "the trial", "the transcript", "the budget", "the dataset" ].freeze
    VERBS = [ "raises", "lowers", "reports", "understates", "confirms", "contradicts" ].freeze

    def sentence(i)
      "#{SUBJECTS[@rng.rand(SUBJECTS.size)].capitalize} #{VERBS[@rng.rand(VERBS.size)]} the figure by #{@rng.rand(90) + 1}% (#{i}-#{@rng.rand(10_000)})."
    end

    def measure_unbatched(h, author)
      t = clock
      SAMPLE.times { |i| h.create_claim(author, "Rate sample #{i} #{@rng.rand(10_000)}.", type: "OBSERVATIONAL") }
      SAMPLE / (clock - t)
    end

    # A \r frame redraws one line on a terminal and is invisible to everything
    # else: a 100k seed left 79 bytes in `docker logs` after 21 hours, and how
    # far it had got had to be reconstructed from row counts
    # (docs/profiler/2026-09-20-seed-write-path-decay.md). Off a terminal, each
    # batch gets its own newline-terminated line with the time on it, because the
    # reader is a log and the question it answers is "when".
    def report(made, before, started)
      appended = Contribution.count - before
      rate = appended / (clock - started)
      if tty?
        @out.printf("\r  %d/%d claims · %d contributions · %.0f/s", made, @claims, appended, rate)
        @out.puts if made >= @claims
      else
        @out.printf("%s  %d/%d claims · %d contributions · %.0f/s\n", Time.now.utc.iso8601, made, @claims, appended, rate)
      end
      @out.flush
    end

    def tty? = @out.respond_to?(:tty?) && @out.tty?
  end
end
