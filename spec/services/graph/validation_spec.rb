require "rails_helper"

RSpec.describe "Graph payload validation" do
  let(:pair) { register_key.first }
  let(:content) { "In the narrative, Azazel teaches humans the making of swords, knives, shields, and related metal implements." }
  let(:source) { create_source(pair, content: content) }

  it "verifies source content and location excerpts against their hashes" do
    expect_rejected("CONTENT_HASH_MISMATCH") { create_source(pair, content: "abc", content_hash: Crypto::Hashing.bytes("abd")) }
    expect_rejected("SCHEMA_INVALID") { create_source(pair, type: "BLOG") }

    expect(create_location(pair, source, start: 18, finish: 24).excerpt).to eq("Azazel")
    expect_rejected("EXCERPT_MISMATCH") { create_location(pair, source, start: 18, finish: 24, excerpt: "Azazil", excerpt_hash: Crypto::Hashing.bytes("Azazil")) }
    expect_rejected("EXCERPT_HASH_MISMATCH") { create_location(pair, source, start: 18, finish: 24, excerpt_hash: Crypto::Hashing.bytes("other")) }
    expect_rejected("LOCATOR_INVALID") { create_location(pair, source, start: 5, finish: 5000) }
    expect_rejected("LOCATOR_INVALID") { create_location(pair, source, start: 10, finish: 4) }
    expect_rejected("TARGET_UNKNOWN") { create_location(pair, Source.new(id: SecureRandom.uuid, content: content)) }
  end

  it "defaults truth_evaluable by claim type and requires a reason when false" do
    expect(create_claim(pair, "Companies should adopt remote work.", type: "NORMATIVE")).to have_attributes(truth_evaluable: false, not_evaluable_reason: "NORMATIVE_OR_VALUE")
    expect(create_claim(pair, "It will rain tomorrow.", type: "FORECAST")).to have_attributes(truth_evaluable: false, not_evaluable_reason: "UNRESOLVED_FORECAST")
    expect(create_claim(pair, "Remote work causes higher productivity.", type: "CAUSAL")).to have_attributes(truth_evaluable: true, not_evaluable_reason: nil)
    expect(create_claim(pair, "Unknowable.", type: "HISTORICAL", truth_evaluable: false, not_evaluable_reason: "UNTESTABLE_CURRENT_METHODS").not_evaluable_reason).to eq("UNTESTABLE_CURRENT_METHODS")
    expect_rejected("SCHEMA_INVALID") { create_claim(pair, "x", type: "HISTORICAL", truth_evaluable: false) }
    expect_rejected("SCHEMA_INVALID") { create_claim(pair, "x", type: "HISTORICAL", not_evaluable_reason: "RHETORICAL") }
    expect_rejected("SCHEMA_INVALID") { create_claim(pair, "x", type: "OPINION") }
    expect_rejected("SCHEMA_INVALID") { create_claim(pair, "") }
  end

  it "validates evidence, links, edges, and groups against the closed lists" do
    location = create_location(pair, source)
    claim = create_claim(pair, "The narrative attributes metalworking instruction to Azazel.")
    evidence = create_evidence(pair, location, assessment: { "authenticity" => "DOUBTFUL" })
    expect(evidence.assessment).to eq("authenticity" => "DOUBTFUL", "extraction" => "UNVERIFIED")
    expect_rejected("SCHEMA_INVALID") { create_evidence(pair, location, observation: "GUESS") }
    expect_rejected("SCHEMA_INVALID") { create_evidence(pair, location, assessment: { "authenticity" => "TRUSTED" }) }

    expect(link_evidence(pair, evidence, claim, steps: 5)).to be_persisted
    expect_rejected("SCHEMA_INVALID") { link_evidence(pair, evidence, claim, steps: 6) }
    expect_rejected("SCHEMA_INVALID") { link_evidence(pair, evidence, claim, direction: "PROVES") }
    expect_rejected("SCHEMA_INVALID") { link_evidence(pair, evidence, claim, strength: "OVERWHELMING") }

    other = create_claim(pair, "Another.")
    expect_rejected("SCHEMA_INVALID") { create_edge(pair, claim, claim) }
    expect_rejected("SCHEMA_INVALID") { create_edge(pair, claim, other, type: "LIKES") }
    expect(create_edge(pair, claim, other, type: "SAME_AS")).to be_persisted

    group = create_group(pair, type: "SAME_PRIMARY_TEXT")
    expect_rejected("SCHEMA_INVALID") { create_group(pair, type: "SAME_VIBES") }
    assignment = assign_group(pair, evidence, group)
    expect(evidence.reload.independence_group_id).to eq(group.id)
    expect(evidence.independence_group_at(assignment.accepted_seq - 1)).to be_nil
    expect(evidence.independence_group_at(assignment.accepted_seq)).to eq(group)

    invalidate(pair, assignment.contribution)
    expect(evidence.reload.independence_group_id).to be_nil
  end

  it "flags non-atomic claims with warnings only" do
    expect(Claims::Atomicity.warnings("Acme's 2026 survey reports that 62% of respondents said their productivity was higher when remote.")).to eq([])
    codes = Claims::Atomicity.warnings("The Watchers descended, taught metallurgy, fathered giants, and caused corruption.").map { |w| w[:code] }
    expect(codes).to include("ATOMICITY_SERIAL")
    long = (1..30).map { |i| "word#{i}" }.join(" ")
    expect(Claims::Atomicity.warnings(long).map { |w| w[:code] }).to include("ATOMICITY_LONG")
  end
end
