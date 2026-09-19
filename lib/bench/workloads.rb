# frozen_string_literal: true

module Bench
  # The operations worth measuring, in one place so that bench:report times the
  # same things bench:cpu and bench:memory profile. Each value is a lambda that
  # performs the operation once against whatever corpus the database holds.
  class Workloads
    def self.call(...) = new(...).call

    def initialize(base_url: ENV.fetch("LEDGER_BASE_URL", "http://localhost:3000"))
      @base_url = base_url
      @rack = Rack::MockRequest.new(Rails.application)
    end

    # {name => lambda}. Entries whose fixture is missing are left out rather
    # than raising, so a small or empty corpus still reports what it can.
    def call
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

    # One workload by a case-insensitive substring of its name, so a rake
    # argument need not carry spaces and punctuation exactly. [name, lambda],
    # or [nil, nil] when nothing matches.
    def self.find(query)
      list = call
      name = query.present? ? list.keys.find { |k| k.downcase.include?(query.to_s.downcase) } : nil
      [ name, name && list[name] ]
    end

    def self.names = call.keys

    private

    def get(path)
      res = @rack.get(path, "HTTP_HOST" => "localhost", "REMOTE_ADDR" => "127.0.0.1")
      raise "#{path} returned #{res.status}" unless res.status < 400

      res
    end
  end
end
