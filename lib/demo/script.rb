# frozen_string_literal: true

module Demo
  # What every seeded demo shares: the cast (Curator and Reviewer with
  # server-custodied keys; Alice → AgentVerifier and Mallory → AgentBad as
  # self-custodied principals and agents), display handles, checkpoints, and
  # the result the report reads.
  class Script
    Result = Struct.new(:handles, :checkpoints, :claims, keyword_init: true)

    def self.run(helpers = Helpers.new) = new(helpers).run

    def initialize(helpers)
      @h = helpers
      @x = {}
      @cp = {}
    end

    private

    # Registers the cast and the two in-process agents. Returns [curator, reviewer] users.
    def cast(domains:)
      h = @h
      _, _, curator = h.register_server_user("curator@demo.galedra", display_name: "Curator")
      _, _, reviewer = h.register_server_user("reviewer@demo.galedra", display_name: "Reviewer", identity_tier: "ESTABLISHED")
      alice, = h.register_key(display_name: "Alice")
      verifier_key, verifier = h.register_key(kind: "AGENT", display_name: "AgentVerifier")
      mallory, = h.register_key(display_name: "Mallory")
      bad_key, bad = h.register_key(kind: "AGENT", display_name: "AgentBad")
      # A second honest volunteer. Since the system accepts an extraction
      # (2026-09-19), the claims belong to whoever extracted them, and a
      # principal never checks its own claim (04 §3.1, Article XI). So the
      # checks on what AgentVerifier extracted are answered by someone else,
      # which is how this works outside a demo anyway.
      bob, = h.register_key(display_name: "Bob")
      checker_key, checker = h.register_key(kind: "AGENT", display_name: "AgentChecker")
      h.agent(:verifier, key: verifier_key, delegation: h.delegate(alice, verifier, domains: domains))
      h.agent(:bad, key: bad_key, delegation: h.delegate(mallory, bad, domains: domains), fixtures_agent: "bad")
      h.agent(:checker, key: checker_key, delegation: h.delegate(bob, checker, domains: domains))
      [ curator, reviewer ]
    end

    def checkpoint(name, label)
      @cp[name] = @h.snapshot("#{name} #{label}").seq
    end

    def result
      Result.new(handles: @x, checkpoints: @cp, claims: @x.select { |k, _| k.match?(/\AC\d\z/) })
    end
  end
end
