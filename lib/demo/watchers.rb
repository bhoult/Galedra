# frozen_string_literal: true

module Demo
  # The Watchers stress test (examples/watchers §6).
  class Watchers
    DOMAIN = "ancient_near_east"
    Result = Struct.new(:handles, :checkpoints, :claims, keyword_init: true)

    def self.run(helpers = Helpers.new) = new(helpers).run

    def initialize(helpers)
      @h = helpers
      @x = {}
      @cp = {}
    end

    def run
      h = @h
      _, _, curator = h.register_server_user("curator@demo.galedra", display_name: "Curator")
      _, _, reviewer = h.register_server_user("reviewer@demo.galedra", display_name: "Reviewer", identity_tier: "ESTABLISHED")
      alice, = h.register_key(display_name: "Alice")
      verifier_key, verifier = h.register_key(kind: "AGENT", display_name: "AgentVerifier")
      mallory, = h.register_key(display_name: "Mallory")
      bad_key, bad = h.register_key(kind: "AGENT", display_name: "AgentBad")
      h.agent(:verifier, key: verifier_key, delegation: h.delegate(alice, verifier, domains: [ DOMAIN ]))
      h.agent(:bad, key: bad_key, delegation: h.delegate(mallory, bad, domains: [ DOMAIN ]), fixtures_agent: "bad")

      @x["SA"] = h.create_source(curator, title: "Watcher narrative A", content: "In the narrative, Azazel teaches humans the making of swords, knives, shields, and related metal implements.")
      @x["SD"] = h.create_source(curator, title: "Mock commentary", type: "SECONDARY_TEXT", content: "A mock commentary: the passage can be read as a critique of transmitting specialized technical knowledge.")
      sla = h.create_location(curator, @x["SA"])
      sld = h.create_location(curator, @x["SD"])
      @x["C1"] = h.create_claim(curator, "The seeded Watcher narrative attributes metalworking instruction to Azazel.", type: "TEXTUAL")
      @x["C2"] = h.create_claim(curator, "The seeded Watcher narrative associates Azazel's instruction with weapon manufacture.", type: "TEXTUAL")
      @x["C3"] = h.create_claim(curator, "The narrative portrays specialized knowledge transmission as contributing to social corruption.", type: "INTERPRETIVE")
      @x["C4"] = h.create_claim(curator, "The seeded narrative describes the Watchers as artificial or technological beings.", type: "TEXTUAL")
      @x["C6"] = h.create_claim(curator, "Teaching people to make weapons is morally wrong.", type: "NORMATIVE")
      @x["E1"] = h.create_evidence(curator, sla, statement: "Azazel teaches the making of swords, knives, shields, and metal implements.")
      @x["E2"] = h.create_evidence(curator, sld, observation: "EXPERT_ANALYSIS", statement: "Commentary reads the passage as a critique of transmitting technical knowledge.")
      @x["E3"] = h.create_evidence(curator, sla, statement: "The excerpt contains no description of the Watchers as artificial or technological.")
      @x["G1"] = h.create_group(curator, type: "SAME_PRIMARY_TEXT", description: "source SA")
      h.assign(curator, @x["E1"], @x["G1"])
      h.assign(curator, @x["E3"], @x["G1"])
      @x["L1"] = h.link(curator, @x["E1"], @x["C1"])
      @x["L3"] = h.link(curator, @x["E2"], @x["C3"], strength: "MODERATE", steps: 1)
      @x["L4"] = h.link(curator, @x["E3"], @x["C4"], direction: "CONTRADICT", strength: "MODERATE")
      %w[L1 L3 L4].each { |l| h.audit(reviewer, @x[l]) }
      @x["T1"] = h.create_task("EVIDENCE_VERIFICATION", @x["C2"], location: sla, domain: DOMAIN)
      t1 = h.run_task(:verifier, @x["T1"])
      @x["L2"] = EvidenceClaimLink.find_by!(contribution_id: t1.id)
      @x["T2"] = h.create_task("OPPOSING_EVIDENCE_SEARCH", @x["C4"], domain: DOMAIN)
      h.run_task(:verifier, @x["T2"])
      checkpoint("S1", "baseline")

      @x["C5"] = h.create_claim(curator, "The source explicitly identifies Azazel as a machine.", type: "TEXTUAL")
      @x["T3"] = h.create_task("EVIDENCE_VERIFICATION", @x["C5"], location: sla, domain: DOMAIN)
      t3 = h.run_task(:bad, @x["T3"])
      @x["L5"] = EvidenceClaimLink.find_by!(contribution_id: t3.id)
      checkpoint("S2", "poisoned")

      @x["T3.schedule"] = AuditSchedule.find_by!(contribution_id: t3.id)
      h.audit(reviewer, t3, result: "SUBSTANTIVE_ERROR", note: "No such statement appears in the cited passage.")
      h.audit(reviewer, t1)
      checkpoint("S3", "audited")

      @x["SB"] = h.create_source(curator, title: "Second retelling", content: "A second retelling says Azazel showed people how to work metals and forge weapons of war.")
      @x["SC"] = h.create_source(curator, title: "Explainer", type: "SECONDARY_TEXT", content: "An explainer article restates the second retelling: Azazel taught the forging of weapons.")
      @x["E4"] = h.create_evidence(curator, h.create_location(curator, @x["SB"]), statement: "A second retelling says Azazel showed people how to work metals and forge weapons.")
      @x["E5"] = h.create_evidence(curator, h.create_location(curator, @x["SC"]), statement: "An explainer restates that Azazel taught weapon forging.")
      @x["L6"] = h.link(curator, @x["E4"], @x["C1"], strength: "STRONG")
      @x["L7"] = h.link(curator, @x["E5"], @x["C1"], strength: "MODERATE")
      %w[L6 L7].each { |l| h.audit(reviewer, @x[l]) }
      checkpoint("S4", "ungrouped")

      @x["T4"] = h.create_task("SOURCE_INDEPENDENCE_CHECK", @x["C1"], domain: DOMAIN)
      t4 = h.run_task(:verifier, @x["T4"])
      h.audit(reviewer, t4, type: "INDEPENDENCE_CHECK")
      checkpoint("S5", "final")

      Result.new(handles: @x, checkpoints: @cp, claims: @x.select { |k, _| k.match?(/\AC\d\z/) })
    end

    def checkpoint(name, label)
      @cp[name] = @h.snapshot("#{name} #{label}").seq
    end
  end
end
