# frozen_string_literal: true

module Demo
  # The public demo (spec 08 §7), every step a contribution through the real
  # write path, tasks answered by the fixture-driven example agent.
  class PublicDemo < Script
    MEMO = "Remote work boosts productivity: 62% of remote workers report higher productivity (Journal of Distributed Work Research, 2025). Companies should adopt remote work."

    def run
      h = @h
      curator, reviewer = cast(domains: [ "general" ])

      # 2. the memo
      @x["SD"] = h.create_source(curator, title: "AI-drafted memo", type: "OTHER", content: MEMO)
      @x["SD.loc"] = h.create_location(curator, @x["SD"])
      # 3. T0 extraction by AgentVerifier; the Curator accepts the proposals
      @x["T0"] = h.create_task("CLAIM_EXTRACTION", @x["SD"])
      t0 = h.run_task(:verifier, @x["T0"])
      @x["C2"], @x["C4"], @x["C5"], @x["C6"] = Claim.where(contribution_id: t0.id).order(:created_seq).to_a
      h.accept(curator, t0)
      # 4. sources and the Curator's own claims
      @x["SR"] = h.create_source(curator, title: "Acme Remote Work Survey 2026", type: "DATASET",
                                 content: "Acme Remote Work Survey 2026. Respondents: 400 remote employees recruited from Acme customer accounts. Self-reported: 62% said their productivity was higher when working remotely.")
      @x["SP"] = h.create_source(curator, title: "Acme press release", content: "Acme press release: 62% of remote workers report higher productivity, according to Acme's 2026 survey.")
      (1..3).each { |i| @x["SN#{i}"] = h.create_source(curator, title: "News article #{i}", type: "SECONDARY_TEXT", content: "Article #{i}: 62% of remote workers report higher productivity, the article states, citing Acme's press release.") }
      @x["SX"] = h.create_source(curator, title: "Journal of Distributed Work Research 2025 contents", type: "WEBSITE",
                                 content: "Journal of Distributed Work Research, volume 2025, table of contents: no article on remote-work productivity appears.")
      loc = %w[SR SP SN1 SN2 SN3 SX].to_h { |s| [ s, h.create_location(curator, @x[s]) ] }
      @x["C1"] = h.create_claim(curator, "The Acme press release states that 62% of remote workers report higher productivity.", type: "TEXTUAL")
      @x["C3"] = h.create_claim(curator, "62% of 400 remote employees of Acme customers surveyed by Acme in 2026 reported higher productivity.", type: "QUANTITATIVE")
      # 5. evidence and groups
      @x["E1"] = h.create_evidence(curator, loc["SR"], observation: "DATASET_RESULT", statement: "62% of 400 surveyed respondents reported higher productivity.")
      @x["E2"] = h.create_evidence(curator, loc["SP"], statement: "The release states the 62% figure, citing Acme's survey.")
      (1..3).each { |i| @x["E#{i + 2}"] = h.create_evidence(curator, loc["SN#{i}"], statement: "Article #{i} states the 62% figure, citing the release.") }
      @x["E7"] = h.create_evidence(curator, loc["SX"], statement: "The journal's 2025 contents list no article on remote-work productivity.")
      @x["G1"] = h.create_group(curator, type: "SAME_DATASET", description: "Acme 2026 survey")
      @x["G2"] = h.create_group(curator, type: "OTHER", description: "publisher index")
      h.assign(curator, @x["E1"], @x["G1"])
      h.assign(curator, @x["E2"], @x["G1"])
      h.assign(curator, @x["E7"], @x["G2"])
      # 6. links
      @x["L1"] = h.link(curator, @x["E2"], @x["C1"])
      @x["L2"] = h.link(curator, @x["E1"], @x["C3"])
      @x["L3"] = h.link(curator, @x["E1"], @x["C2"], strength: "STRONG", steps: 1, note: "survey to population")
      %w[E2 E3 E4 E5].each_with_index { |e, i| @x["L#{4 + i}"] = h.link(curator, @x[e], @x["C2"], strength: "MODERATE", steps: 1, note: "as first extracted") }
      @x["L8"] = h.link(curator, @x["E7"], @x["C4"], direction: "CONTRADICT", strength: "MODERATE", note: "an index snapshot can be incomplete, so not STRONG")
      @x["L9"] = h.link(curator, @x["E1"], @x["C6"], strength: "WEAK", steps: 2, note: "a satisfaction survey is not a causal design")
      # 7. T1 opposing search on C4 → NONE_FOUND
      @x["T1"] = h.create_task("OPPOSING_EVIDENCE_SEARCH", @x["C4"])
      t1 = h.run_task(:verifier, @x["T1"])
      # 8. audits
      h.audit(reviewer, t0, type: "SCHEMA_CHECK")
      h.audit(reviewer, t1)
      (1..9).each { |i| h.audit(reviewer, @x["L#{i}"]) }
      checkpoint("S1", "as drafted")
      # 9. T2 verification of C4 on the press release, by AgentBad
      @x["T2"] = h.create_task("EVIDENCE_VERIFICATION", @x["C4"], location: loc["SP"])
      t2 = h.run_task(:bad, @x["T2"])
      @x["L10"] = EvidenceClaimLink.find_by!(contribution_id: t2.id)
      checkpoint("S2", "poisoned")
      # 10–11. sampled, audited, invalidated by the system
      @x["T2.schedule"] = AuditSchedule.find_by!(contribution_id: t2.id)
      @x["A-T2"] = h.audit(reviewer, t2, result: "SUBSTANTIVE_ERROR", note: "The press release is not the cited journal article.")
      checkpoint("S3", "audited")
      # 12–13. T3 independence check on C2
      @x["T3"] = h.create_task("SOURCE_INDEPENDENCE_CHECK", @x["C2"])
      t3 = h.run_task(:verifier, @x["T3"])
      h.audit(reviewer, t3, type: "INDEPENDENCE_CHECK")
      checkpoint("S4", "grouped")
      # 14–15. T4 qualifier check on C2: proposal, accepted and audited by the Reviewer
      @x["T4"] = h.create_task("QUALIFIER_CHECK", @x["C2"])
      t4 = h.run_task(:verifier, @x["T4"])
      raise "T4 should be a proposal" unless t4.reload.current_status == "PENDING"

      h.accept(reviewer, t4)
      h.audit(reviewer, t4)
      @x["E6"] = EvidenceItem.find_by!(contribution_id: t4.id)
      h.assign(curator, @x["E6"], @x["G1"])
      checkpoint("S5", "qualified")
      result
    end
  end
end
