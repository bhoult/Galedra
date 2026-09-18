# Builds the public demo (08 §7) and the Watchers stress test (examples/watchers §6)
# through the real write path: leased tasks answered by TASK_RESULT envelopes,
# audits, sampling, and acceptance. Stage 11's seeds are the real scripts with
# the example agent; this is test scaffolding that mirrors them step for step.
module DemoGraphs
  # Every golden field is now reproducible end to end.
  DEFERRED_GOLDEN_FIELDS = [].freeze

  Graph = Struct.new(:claims, :checkpoints, :handles, keyword_init: true)

  def golden_cases_for(suite)
    golden["cases"].select { |k| k["suite"] == suite }
  end

  def build_public_demo
    curator, = register_key(display_name: "Curator")
    reviewer, = register_key(display_name: "Reviewer", identity_tier: "ESTABLISHED")
    _alice, verifier, _verifier_c, verifier_delegation = principal_with_agent
    mallory, bad, _bad_c, bad_delegation = principal_with_agent
    h = {}
    cp = {}

    memo = "Remote work boosts productivity: 62% of remote workers report higher productivity (Journal of Distributed Work Research, 2025). Companies should adopt remote work."
    h["SD"] = create_source(curator, title: "AI-drafted memo", type: "OTHER", content: memo)
    create_location(curator, h["SD"])

    # T0 CLAIM_EXTRACTION by the verifier: one result proposing C2, C4, C5, C6; the Curator accepts it
    h["T0"] = create_task("CLAIM_EXTRACTION", h["SD"])
    extraction = submit_result(verifier, h["T0"], delegation: verifier_delegation, outcome: "CLAIMS_FOUND", ops: [
      { "op" => "CREATE_CLAIM", "canonical_text" => "62% of remote workers report higher productivity.", "claim_type" => "QUANTITATIVE", "affirms_not_private_individual" => true },
      { "op" => "CREATE_CLAIM", "canonical_text" => "The Journal of Distributed Work Research (2025) reports that 62% of remote workers report higher productivity.", "claim_type" => "TEXTUAL", "affirms_not_private_individual" => true },
      { "op" => "CREATE_CLAIM", "canonical_text" => "Companies should adopt remote work.", "claim_type" => "NORMATIVE", "affirms_not_private_individual" => true },
      { "op" => "CREATE_CLAIM", "canonical_text" => "Remote work causes higher productivity.", "claim_type" => "CAUSAL", "affirms_not_private_individual" => true }
    ])
    h["C2"], h["C4"], h["C5"], h["C6"] = result_rows(extraction, Claim)
    accept(curator, extraction.contribution)

    h["SR"] = create_source(curator, title: "Acme Remote Work Survey 2026", type: "DATASET",
                            content: "Acme Remote Work Survey 2026. Respondents: 400 remote employees recruited from Acme customer accounts. Self-reported: 62% said their productivity was higher when working remotely.")
    h["SP"] = create_source(curator, title: "Acme press release", type: "PRIMARY_TEXT",
                            content: "Acme press release: 62% of remote workers report higher productivity, according to Acme's 2026 survey.")
    %w[SN1 SN2 SN3].each_with_index do |s, i|
      h[s] = create_source(curator, title: "News article #{i + 1}", type: "SECONDARY_TEXT",
                           content: "Article #{i + 1}: 62% of remote workers report higher productivity, the article states, citing Acme's press release.")
    end
    h["SX"] = create_source(curator, title: "Journal of Distributed Work Research 2025 contents", type: "WEBSITE",
                            content: "Journal of Distributed Work Research, volume 2025, table of contents: no article on remote-work productivity appears.")
    loc = %w[SD SR SP SN1 SN2 SN3 SX].to_h { |s| [ s, s == "SD" ? SourceLocation.find_by!(source_id: h["SD"].id) : create_location(curator, h[s]) ] }
    h["C1"] = create_claim(curator, "The Acme press release states that 62% of remote workers report higher productivity.", type: "TEXTUAL")
    h["C3"] = create_claim(curator, "62% of 400 remote employees of Acme customers surveyed by Acme in 2026 reported higher productivity.", type: "QUANTITATIVE")

    h["E1"] = create_evidence(curator, loc["SR"], observation: "DATASET_RESULT", statement: "62% of 400 surveyed respondents reported higher productivity.")
    h["E2"] = create_evidence(curator, loc["SP"], statement: "The release states the 62% figure, citing Acme's survey.")
    %w[E3 E4 E5].each_with_index { |e, i| h[e] = create_evidence(curator, loc["SN#{i + 1}"], statement: "Article #{i + 1} states the 62% figure, citing the release.") }
    h["E7"] = create_evidence(curator, loc["SX"], statement: "The journal's 2025 contents list no article on remote-work productivity.")
    h["G1"] = create_group(curator, type: "SAME_DATASET", description: "Acme 2026 survey")
    h["G2"] = create_group(curator, type: "OTHER", description: "publisher index")
    assign_group(curator, h["E1"], h["G1"])
    assign_group(curator, h["E2"], h["G1"])
    assign_group(curator, h["E7"], h["G2"])

    h["L1"] = link_evidence(curator, h["E2"], h["C1"], strength: "DIRECT", steps: 0)
    h["L2"] = link_evidence(curator, h["E1"], h["C3"], strength: "DIRECT", steps: 0)
    h["L3"] = link_evidence(curator, h["E1"], h["C2"], strength: "STRONG", steps: 1, note: "survey to population")
    %w[E2 E3 E4 E5].each_with_index { |e, i| h["L#{4 + i}"] = link_evidence(curator, h[e], h["C2"], strength: "MODERATE", steps: 1, note: "as first extracted #{i}") }
    h["L8"] = link_evidence(curator, h["E7"], h["C4"], direction: "CONTRADICT", strength: "MODERATE", steps: 0, note: "an index snapshot can be incomplete")
    h["L9"] = link_evidence(curator, h["E1"], h["C6"], strength: "WEAK", steps: 2, note: "a satisfaction survey is not a causal design")
    # Step 7: T1 OPPOSING_EVIDENCE_SEARCH on C4 (direction SUPPORT) finds nothing
    h["T1"] = create_task("OPPOSING_EVIDENCE_SEARCH", h["C4"])
    t1 = submit_result(verifier, h["T1"], delegation: verifier_delegation, outcome: "NONE_FOUND", ops: [])
    # Step 8: Reviewer audits T0, T1, and each Curator link contribution
    audit(reviewer, extraction.contribution, type: "SCHEMA_CHECK")
    audit(reviewer, t1.contribution, type: "SOURCE_CHECK")
    (1..9).each { |i| audit(reviewer, h["L#{i}"]) }
    cp["S1"] = Contribution.maximum(:seq)

    # Step 9: T2 EVIDENCE_VERIFICATION of C4 on the press-release location, answered by AgentBad
    h["T2"] = create_task("EVIDENCE_VERIFICATION", h["C4"], location: loc["SP"])
    t2 = submit_result(bad, h["T2"], delegation: bad_delegation, outcome: "CONFIRMED", ops: [
      { "op" => "LINK_EVIDENCE", "evidence_item_id" => h["E2"].id, "claim_id" => h["C4"].id, "direction" => "SUPPORT", "relevance_strength" => "DIRECT", "interpretive_steps" => 0, "note" => "Release states the same figure." }
    ])
    h["L10"] = result_rows(t2, EvidenceClaimLink).first
    cp["S2"] = Contribution.maximum(:seq)

    # Steps 10–11: sampled (n=0, mean 0.5), audited SUBSTANTIVE_ERROR; the system invalidates
    audit(reviewer, t2.contribution, result: "SUBSTANTIVE_ERROR", note: "The press release is not the cited journal article.")
    cp["S3"] = Contribution.maximum(:seq)

    # Steps 12–13: T3 SOURCE_INDEPENDENCE_CHECK on C2 groups the articles into G1
    h["T3"] = create_task("SOURCE_INDEPENDENCE_CHECK", h["C2"])
    t3 = submit_result(verifier, h["T3"], delegation: verifier_delegation, outcome: "GROUPED",
                       ops: %w[E3 E4 E5].map { |e| { "op" => "ASSIGN_INDEPENDENCE_GROUP", "evidence_item_id" => h[e].id, "independence_group_id" => h["G1"].id } })
    audit(reviewer, t3.contribution, type: "INDEPENDENCE_CHECK")
    cp["S4"] = Contribution.maximum(:seq)

    # Steps 14–15: T4 QUALIFIER_CHECK on C2: E6, L16, the NARROWS edge, and supersessions of L3–L7 (a proposal until the Reviewer accepts)
    h["T4"] = create_task("QUALIFIER_CHECK", h["C2"])
    t4 = submit_result(verifier, h["T4"], delegation: verifier_delegation, outcome: "QUALIFIERS_FOUND", ops: [
      { "op" => "CREATE_EVIDENCE", "ref" => "e6", "source_location_id" => loc["SR"].id, "observation_type" => "DATASET_RESULT",
        "statement" => "Respondents were recruited only from Acme customer accounts; answers are self-reported." },
      { "op" => "LINK_EVIDENCE", "evidence_item_id" => "e6", "claim_id" => h["C2"].id, "direction" => "QUALIFY", "relevance_strength" => "DIRECT", "interpretive_steps" => 0 },
      { "op" => "CREATE_CLAIM_EDGE", "from_claim_id" => h["C3"].id, "to_claim_id" => h["C2"].id, "relationship_type" => "NARROWS" }
    ] + (3..7).map { |i| { "op" => "SUPERSEDE_LINK", "link_id" => h["L#{i}"].id, "direction" => "SUPPORT", "relevance_strength" => "WEAK", "interpretive_steps" => 3,
                            "reason" => "customer sample, self-report: little about all remote workers" } })
    expect(t4.acceptance).to be_nil
    accept(reviewer, t4.contribution)
    audit(reviewer, t4.contribution)
    h["E6"] = result_rows(t4, EvidenceItem).first
    assign_group(curator, h["E6"], h["G1"])
    links = result_rows(t4, EvidenceClaimLink)
    h["L16"] = links.find { |l| l.direction == "QUALIFY" }
    links.select { |l| l.supersedes_link_id }.each_with_index { |l, i| h["L#{11 + i}"] = l }
    cp["S5"] = Contribution.maximum(:seq)

    Graph.new(claims: h.select { |k, _| k.start_with?("C") }, checkpoints: cp, handles: h)
  end

  def build_watchers_demo
    curator, = register_key(display_name: "Curator")
    reviewer, = register_key(display_name: "Reviewer", identity_tier: "ESTABLISHED")
    _alice, verifier, _vc, verifier_delegation = principal_with_agent
    mallory, bad, _bc, bad_delegation = principal_with_agent
    h = {}
    cp = {}

    h["SA"] = create_source(curator, title: "Watcher narrative A", content: "In the narrative, Azazel teaches humans the making of swords, knives, shields, and related metal implements.")
    h["SD"] = create_source(curator, title: "Mock commentary", type: "SECONDARY_TEXT", content: "A mock commentary: the passage can be read as a critique of transmitting specialized technical knowledge.")
    loc = { "SA" => create_location(curator, h["SA"]), "SD" => create_location(curator, h["SD"]) }
    h["C1"] = create_claim(curator, "The seeded Watcher narrative attributes metalworking instruction to Azazel.")
    h["C2"] = create_claim(curator, "The seeded Watcher narrative associates Azazel's instruction with weapon manufacture.")
    h["C3"] = create_claim(curator, "The narrative portrays specialized knowledge transmission as contributing to social corruption.", type: "INTERPRETIVE")
    h["C4"] = create_claim(curator, "The seeded narrative describes the Watchers as artificial or technological beings.")
    h["C6"] = create_claim(curator, "Teaching people to make weapons is morally wrong.", type: "NORMATIVE")
    h["E1"] = create_evidence(curator, loc["SA"], statement: "Azazel teaches the making of swords, knives, shields, and metal implements.")
    h["E2"] = create_evidence(curator, loc["SD"], observation: "EXPERT_ANALYSIS", statement: "Commentary reads the passage as a critique of transmitting technical knowledge.")
    h["E3"] = create_evidence(curator, loc["SA"], statement: "The excerpt contains no description of the Watchers as artificial or technological.")
    h["G1"] = create_group(curator, type: "SAME_PRIMARY_TEXT", description: "source SA")
    assign_group(curator, h["E1"], h["G1"])
    assign_group(curator, h["E3"], h["G1"])
    h["L1"] = link_evidence(curator, h["E1"], h["C1"], strength: "DIRECT", steps: 0)
    h["L3"] = link_evidence(curator, h["E2"], h["C3"], strength: "MODERATE", steps: 1)
    h["L4"] = link_evidence(curator, h["E3"], h["C4"], direction: "CONTRADICT", strength: "MODERATE", steps: 0)
    %w[L1 L3 L4].each { |l| audit(reviewer, h[l]) }
    # T1 EVIDENCE_VERIFICATION of C2 on SLA: CONFIRMED with L2
    h["T1"] = create_task("EVIDENCE_VERIFICATION", h["C2"], location: loc["SA"], domain: "ancient_near_east")
    t1 = submit_result(verifier, h["T1"], delegation: verifier_delegation, outcome: "CONFIRMED", ops: [
      { "op" => "LINK_EVIDENCE", "evidence_item_id" => h["E1"].id, "claim_id" => h["C2"].id, "direction" => "SUPPORT", "relevance_strength" => "DIRECT", "interpretive_steps" => 0 }
    ])
    h["L2"] = result_rows(t1, EvidenceClaimLink).first
    # T2 OPPOSING_EVIDENCE_SEARCH on C4: NONE_FOUND
    h["T2"] = create_task("OPPOSING_EVIDENCE_SEARCH", h["C4"], domain: "ancient_near_east")
    submit_result(verifier, h["T2"], delegation: verifier_delegation, outcome: "NONE_FOUND", ops: [])
    cp["S1"] = Contribution.maximum(:seq)

    h["C5"] = create_claim(curator, "The source explicitly identifies Azazel as a machine.")
    h["T3"] = create_task("EVIDENCE_VERIFICATION", h["C5"], location: loc["SA"], domain: "ancient_near_east")
    t3 = submit_result(bad, h["T3"], delegation: bad_delegation, outcome: "CONFIRMED", ops: [
      { "op" => "LINK_EVIDENCE", "evidence_item_id" => h["E1"].id, "claim_id" => h["C5"].id, "direction" => "SUPPORT", "relevance_strength" => "DIRECT", "interpretive_steps" => 0 }
    ])
    h["L5"] = result_rows(t3, EvidenceClaimLink).first
    cp["S2"] = Contribution.maximum(:seq)

    audit(reviewer, t3.contribution, result: "SUBSTANTIVE_ERROR", note: "No such statement appears in the cited passage.")
    audit(reviewer, t1.contribution)
    cp["S3"] = Contribution.maximum(:seq)

    h["SB"] = create_source(curator, title: "Second retelling", content: "A second retelling says Azazel showed people how to work metals and forge weapons of war.")
    h["SC"] = create_source(curator, title: "Explainer", type: "SECONDARY_TEXT", content: "An explainer article restates the second retelling: Azazel taught the forging of weapons.")
    h["E4"] = create_evidence(curator, create_location(curator, h["SB"]), statement: "A second retelling says Azazel showed people how to work metals and forge weapons.")
    h["E5"] = create_evidence(curator, create_location(curator, h["SC"]), statement: "An explainer restates that Azazel taught weapon forging.")
    h["L6"] = link_evidence(curator, h["E4"], h["C1"], strength: "STRONG", steps: 0)
    h["L7"] = link_evidence(curator, h["E5"], h["C1"], strength: "MODERATE", steps: 0)
    %w[L6 L7].each { |l| audit(reviewer, h[l]) }
    cp["S4"] = Contribution.maximum(:seq)

    # T4 SOURCE_INDEPENDENCE_CHECK on C1: create G2 and assign E4, E5
    h["T4"] = create_task("SOURCE_INDEPENDENCE_CHECK", h["C1"], domain: "ancient_near_east")
    t4 = submit_result(verifier, h["T4"], delegation: verifier_delegation, outcome: "GROUPED", ops: [
      { "op" => "CREATE_INDEPENDENCE_GROUP", "ref" => "g2", "group_type" => "SAME_PRIMARY_TEXT", "description" => "lineage of SB" },
      { "op" => "ASSIGN_INDEPENDENCE_GROUP", "evidence_item_id" => h["E4"].id, "independence_group_id" => "g2" },
      { "op" => "ASSIGN_INDEPENDENCE_GROUP", "evidence_item_id" => h["E5"].id, "independence_group_id" => "g2" }
    ])
    h["G2"] = result_rows(t4, IndependenceGroup).first
    audit(reviewer, t4.contribution, type: "INDEPENDENCE_CHECK")
    cp["S5"] = Contribution.maximum(:seq)

    Graph.new(claims: h.select { |k, _| k.start_with?("C") }, checkpoints: cp, handles: h)
  end
end

RSpec.configure { |c| c.include DemoGraphs }
