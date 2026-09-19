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
      @rack = Rack::MockRequest.new(Rails.application)
    end

    def call
      @out.puts corpus
      @out.puts
      @out.printf("%-42s %9s %9s\n", "operation", "median", "slowest")
      rows.each { |name, block| timed(name, &block) }
      @out.puts
      @out.puts "claim_scores: #{ClaimScore.count} rows for #{Claim.count} claims " \
                "(#{size_of('claim_scores')}), contributions #{size_of('contributions')}"
      @out.puts "measured on #{Etc.uname[:sysname]} #{Etc.nprocessors} cpu, #{Rails.env}, #{Time.now.utc.iso8601}"
    end

    private

    def corpus
      counts = { contributions: Contribution.count, claims: Claim.count, evidence: EvidenceItem.count,
                 links: EvidenceClaimLink.count, sources: Source.count, tasks: Task.count, audits: Audit.count }
      counts.map { |k, v| "#{k} #{v}" }.join(" · ")
    end

    def rows
      seq = Contribution.maximum(:seq)
      model = Scoring::Registry.default_model
      claim = Claim.counted_at(seq).order("random()").first
      root = Section.counted_at(seq).where(parent_id: nil).first
      list = {
        "GET /" => -> { get("/") },
        "GET /claims" => -> { get("/claims") },
        "GET /claims?sort=references" => -> { get("/claims?sort=references") },
        "GET /weaknesses" => -> { get("/weaknesses") },
        "GET /contributors" => -> { get("/contributors") },
        "GET /contributions" => -> { get("/contributions") },
        "GET /tasks" => -> { get("/tasks") }
      }
      list["GET /claims/:id"] = -> { get("/claims/#{claim.id}") } if claim
      list["GET /claims/:id?calculation=1"] = -> { get("/claims/#{claim.id}?calculation=1") } if claim
      list["GET /sections/:root"] = -> { get("/sections/#{root.id}") } if root
      list["GET /api/v1/claims?limit=50"] = -> { get("/api/v1/claims?limit=50") }
      list["GET /api/v1/weaknesses"] = -> { get("/api/v1/weaknesses") }
      if claim && model
        list["Scoring::Score (cached)"] = -> { Scoring::Score.call(claim, seq, model) }
        list["Scoring::Score (cold)"] = lambda {
          ClaimScore.where(claim_id: claim.id, snapshot_seq: seq).delete_all
          Scoring::Score.call(claim, seq, model)
        }
        list["Cards::ClaimCard"] = -> { Cards::ClaimCard.call(claim, seq, model) }
        list["Weaknesses::Report"] = -> { Weaknesses::Report.call(seq, limit: 25) }
      end
      list["Contributors::Tally.top"] = -> { Contributors::Tally.top(limit: 100) }
      list
    end

    def get(path)
      res = @rack.get(path, "HTTP_HOST" => "localhost", "REMOTE_ADDR" => "127.0.0.1")
      raise "#{path} returned #{res.status}" unless res.status < 400

      res
    end

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

    def size_of(table)
      ActiveRecord::Base.connection.select_value("SELECT pg_size_pretty(pg_total_relation_size('#{table}'))")
    end
  end
end
