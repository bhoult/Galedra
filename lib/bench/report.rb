# frozen_string_literal: true

module Bench
  # Times the pages and services that walk the graph, at whatever corpus the
  # database currently holds (Stage 26). Prints one table, so a change can be
  # compared against a recorded baseline rather than a memory.
  class Report
    RUNS = 3

    def self.call(...) = new(...).call

    def initialize(out: $stdout, base_url: ENV.fetch("LEDGER_BASE_URL", "http://localhost:3000"))
      @out = out
      @base_url = base_url
    end

    def call
      @out.puts corpus
      @out.puts
      @out.printf("%-42s %9s %9s\n", "operation", "median", "slowest")
      Isolation.call { rows.each { |name, block| timed(name, &block) } }
      @out.puts
      @out.puts "claim_scores: #{ClaimScore.count} rows for #{Claim.count} claims " \
                "(#{size_of('claim_scores')}), contributions #{size_of('contributions')}"
      @out.puts "#{Isolation.note}, #{Time.now.utc.iso8601}"
    end

    private

    def corpus
      counts = { contributions: Contribution.count, claims: Claim.count, evidence: EvidenceItem.count,
                 links: EvidenceClaimLink.count, sources: Source.count, tasks: Task.count, audits: Audit.count }
      counts.map { |k, v| "#{k} #{v}" }.join(" · ")
    end

    def rows = Workloads.call(base_url: @base_url)

    def timed(name)
      times = RUNS.times.map do
        t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t) * 1000
      end.sort
      @out.printf("%-42s %8.1fms %8.1fms\n", name, times[RUNS / 2], times.last)
    rescue StandardError => e
      @out.printf("%-42s %s\n", name, "skipped: #{e.class}: #{e.message.to_s[0, 60]}")
    end

    # The caller passes literals today, but an identifier interpolated into SQL
    # is a habit worth not having, even in a file that refuses to run outside
    # development (security audit, 2026-09-19).
    SIZED_TABLES = %w[claim_scores contributions].freeze

    def size_of(table)
      raise ArgumentError, "unknown table #{table}" unless SIZED_TABLES.include?(table)

      conn = ActiveRecord::Base.connection
      conn.select_value("SELECT pg_size_pretty(pg_total_relation_size(#{conn.quote(conn.quote_table_name(table))}))")
    end
  end
end
