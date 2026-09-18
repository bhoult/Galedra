# Builds the public demo (08 §7) and the Watchers stress test (examples/watchers §6)
# through the real write path, without the task and audit steps that arrive in
# Stages 7 and 8: agent results are appended under a delegation and accepted by
# a different principal, and the poisoned link is invalidated by its principal.
# Stage 11's seeds are the real scripts; this is test scaffolding.
module DemoGraphs
  # Golden fields not yet reproducible end to end. Stage 8 removes
  # review_coverage (task-derived checks).
  DEFERRED_GOLDEN_FIELDS = %w[review_coverage].freeze

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

    # T0 CLAIM_EXTRACTION: proposals by the verifier, accepted by the Curator
    { "C2" => [ "62% of remote workers report higher productivity.", "QUANTITATIVE" ],
      "C4" => [ "The Journal of Distributed Work Research (2025) reports that 62% of remote workers report higher productivity.", "TEXTUAL" ],
      "C5" => [ "Companies should adopt remote work.", "NORMATIVE" ],
      "C6" => [ "Remote work causes higher productivity.", "CAUSAL" ] }.each do |handle, (text, type)|
      h[handle] = create_claim(verifier, text, type: type, delegation: verifier_delegation)
      accept(curator, h[handle].contribution)
    end

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
    # Step 8: Reviewer audits the extraction proposals and each Curator link contribution
    %w[C2 C4 C5 C6].each { |c| audit(reviewer, h[c], type: "SCHEMA_CHECK") }
    (1..9).each { |i| audit(reviewer, h["L#{i}"]) }
    cp["S1"] = Contribution.maximum(:seq)

    # T2 EVIDENCE_VERIFICATION by AgentBad: the false link, accepted (as a task result would be)
    h["L10"] = link_evidence(bad, h["E2"], h["C4"], strength: "DIRECT", steps: 0, delegation: bad_delegation, note: "Release states the same figure.")
    accept(reviewer, h["L10"].contribution)
    cp["S2"] = Contribution.maximum(:seq)

    # Steps 10–11: sampled, then audited SUBSTANTIVE_ERROR; the system invalidates
    audit(reviewer, h["L10"], result: "SUBSTANTIVE_ERROR", note: "The press release is not the cited journal article.")
    cp["S3"] = Contribution.maximum(:seq)

    %w[E3 E4 E5].each { |e| h["A#{e}"] = assign_group(curator, h[e], h["G1"]) }
    %w[E3 E4 E5].each { |e| audit(reviewer, h["A#{e}"], type: "INDEPENDENCE_CHECK") }
    cp["S4"] = Contribution.maximum(:seq)

    h["E6"] = create_evidence(curator, loc["SR"], observation: "DATASET_RESULT", statement: "Respondents were recruited only from Acme customer accounts; answers are self-reported.")
    assign_group(curator, h["E6"], h["G1"])
    h["L16"] = link_evidence(curator, h["E6"], h["C2"], direction: "QUALIFY", strength: "DIRECT", steps: 0)
    create_edge(curator, h["C3"], h["C2"], type: "NARROWS")
    (3..7).each do |i|
      result = append(action_type: "SUPERSEDE_LINK", key_pair: curator,
                      payload: { "link_id" => h["L#{i}"].id, "direction" => "SUPPORT", "relevance_strength" => "WEAK", "interpretive_steps" => 3,
                                 "reason" => "customer sample, self-report: little about all remote workers" })
      h["L#{i + 8}"] = EvidenceClaimLink.find(Ledger::Ids.derive(result.contribution.id, "link"))
    end
    # Step 15: the qualifier work is audited CONFIRMED
    ([ h["E6"], h["L16"] ] + (11..15).map { |i| h["L#{i}"] }).each { |row| audit(reviewer, row) }
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
    h["L2"] = link_evidence(verifier, h["E1"], h["C2"], strength: "DIRECT", steps: 0, delegation: verifier_delegation)
    accept(reviewer, h["L2"].contribution)
    cp["S1"] = Contribution.maximum(:seq)

    h["C5"] = create_claim(curator, "The source explicitly identifies Azazel as a machine.")
    h["L5"] = link_evidence(bad, h["E1"], h["C5"], strength: "DIRECT", steps: 0, delegation: bad_delegation)
    accept(reviewer, h["L5"].contribution)
    cp["S2"] = Contribution.maximum(:seq)

    audit(reviewer, h["L5"], result: "SUBSTANTIVE_ERROR", note: "No such statement appears in the cited passage.")
    audit(reviewer, h["L2"])
    cp["S3"] = Contribution.maximum(:seq)

    h["SB"] = create_source(curator, title: "Second retelling", content: "A second retelling says Azazel showed people how to work metals and forge weapons of war.")
    h["SC"] = create_source(curator, title: "Explainer", type: "SECONDARY_TEXT", content: "An explainer article restates the second retelling: Azazel taught the forging of weapons.")
    h["E4"] = create_evidence(curator, create_location(curator, h["SB"]), statement: "A second retelling says Azazel showed people how to work metals and forge weapons.")
    h["E5"] = create_evidence(curator, create_location(curator, h["SC"]), statement: "An explainer restates that Azazel taught weapon forging.")
    h["L6"] = link_evidence(curator, h["E4"], h["C1"], strength: "STRONG", steps: 0)
    h["L7"] = link_evidence(curator, h["E5"], h["C1"], strength: "MODERATE", steps: 0)
    %w[L6 L7].each { |l| audit(reviewer, h[l]) }
    cp["S4"] = Contribution.maximum(:seq)

    h["G2"] = create_group(curator, type: "SAME_PRIMARY_TEXT", description: "lineage of SB")
    h["AE4"] = assign_group(curator, h["E4"], h["G2"])
    h["AE5"] = assign_group(curator, h["E5"], h["G2"])
    %w[AE4 AE5].each { |a| audit(reviewer, h[a], type: "INDEPENDENCE_CHECK") }
    cp["S5"] = Contribution.maximum(:seq)

    Graph.new(claims: h.select { |k, _| k.start_with?("C") }, checkpoints: cp, handles: h)
  end
end

RSpec.configure { |c| c.include DemoGraphs }
