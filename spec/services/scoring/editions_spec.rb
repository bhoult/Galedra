require "rails_helper"

# Stage 41, model 0.3.0. A claim may name the edition of a source it is about —
# `qualifiers.source_edition`, a key the spec has listed since 02 §3.3 and which
# nothing read until now. A reading of a different version in the same lineage
# is a reading of a different text, so it weighs nothing.
#
# The case that produced the rule: OpenAI published on 8 September, revised the
# page on the 10th, and two readings taken on the 20th were counted as
# contradicting a claim about what it said on the 8th. The contemporaneous
# account supported it. The claim read CONTRADICTED at 0.1419.
RSpec.describe "A claim that names the edition it is about" do
  include GraphHelpers
  before { release_models }

  let(:v3) { Scoring::Registry.find("ledger-default@0.3.0") }
  let(:v2) { Scoring::Registry.find("ledger-default@0.2.0") }

  # Two versions of one document, and a separate contemporaneous account.
  def graph
    pair, = register_key
    then_version = create_source(pair, title: "The announcement, as published", type: "WEBSITE",
                                 canonical_uri: "https://example.invalid/announcement",
                                 lineage_key: "example.invalid/announcement")
    now_version = create_source(pair, title: "The announcement, revised", type: "WEBSITE",
                                canonical_uri: "https://example.invalid/announcement",
                                lineage_key: "example.invalid/announcement",
                                previous_version_id: then_version.id)
    witness = create_source(pair, title: "A contemporaneous account", type: "SECONDARY_TEXT",
                            canonical_uri: "https://example.invalid/witness")

    claim = row_for(append(action_type: "CREATE_CLAIM", key_pair: pair,
                           payload: claim_payload("The announcement carried a disclaimer when it was published.")
                                      .merge("qualifiers" => { "source_edition" => then_version.id })),
                    "claim", Claim)

    link_evidence(pair, create_evidence(pair, create_location(pair, witness)), claim,
                  direction: "SUPPORT", strength: "STRONG")
    # Two different passages of the revised page, so they are two groups under
    # 0.2.0's origin fallback rather than one passage entered twice.
    later = [ [ "DIRECT", 0, 20 ], [ "STRONG", 20, 40 ] ].map do |strength, from, to|
      location = create_location(pair, now_version, start: from, finish: to)
      link_evidence(pair, create_evidence(pair, location), claim, direction: "CONTRADICT", strength: strength)
    end
    { claim: claim, pair: pair, then_version: then_version, now_version: now_version, later: later }
  end

  it "counts the later readings under 0.2.0 and not under 0.3.0" do
    g = graph
    seq = Contribution.maximum(:seq)
    claim = Claim.find(g[:claim].id)

    before = Scoring::Score.call(claim, seq, v2)
    after = Scoring::Score.call(claim, seq, v3)

    expect(before.contradict_groups).to eq(2), "0.2.0 counts a reading of the revised page against the claim"
    expect(after.contradict_groups).to be_zero, "0.3.0 counts neither of them"
    expect(after.support_groups).to eq(1), "and keeps the contemporaneous account"
    expect(after.assessment_state).not_to eq(before.assessment_state)
  end

  # Not deleted, not hidden, and the trace says why: a reader looking at a
  # contradiction that does not count is owed the word.
  it "keeps the link, and records in the trace that it is another edition" do
    g = graph
    seq = Contribution.maximum(:seq)
    result = Scoring::Score.call(Claim.find(g[:claim].id), seq, v3)

    entries = result.trace["links"].select { |l| l["reason"] == Scoring::Calculate::OTHER_EDITION }
    expect(entries.size).to eq(2)
    expect(entries.map { |l| l["effective_weight"] }.uniq).to eq([ "0.000000" ])
    expect(entries.map { |l| l["edition"] }.uniq).to eq([ "OTHER" ])
    # Every link is still in the trace, including the one that is counted.
    expect(result.trace["links"].size).to eq(3)
  end

  # A qualifier weighs nothing because of its direction, whatever edition it
  # came from, and two readers downstream match on that exact reason.
  it "calls a qualifier non-directional, not another edition" do
    g = graph
    pair = g[:pair]
    location = create_location(pair, g[:now_version], start: 5, finish: 25)
    link_evidence(pair, create_evidence(pair, location, statement: "A qualifying reading."), g[:claim],
                  direction: "QUALIFY", strength: "STRONG")
    seq = Contribution.maximum(:seq)

    trace = Scoring::Score.call(Claim.find(g[:claim].id), seq, v3).trace
    qualifier = trace["links"].find { |l| l["direction"] == "QUALIFY" }

    expect(qualifier["reason"]).to eq(Scoring::Calculate::NON_DIRECTIONAL)
    expect(qualifier["edition"]).to eq("OTHER"), "it is still recorded as another edition"
  end

  it "leaves a claim that names no edition exactly as it was" do
    pair, = register_key
    source = create_source(pair, title: "A source", type: "WEBSITE")
    claim = create_claim(pair, "A claim that names no edition.")
    link_evidence(pair, create_evidence(pair, create_location(pair, source)), claim)
    seq = Contribution.maximum(:seq)

    under_two = Scoring::Score.call(Claim.find(claim.id), seq, v2)
    under_three = Scoring::Score.call(Claim.find(claim.id), seq, v3)

    expect(under_three.assessment_state).to eq(under_two.assessment_state)
    expect(under_three.probability).to eq(under_two.probability)
    expect(under_three.support_groups).to eq(under_two.support_groups)
  end

  # The older models must be reproducible byte for byte: a rule declared by one
  # model is not allowed to leak into another (Invariant 4).
  it "does not appear in the trace of a model that does not declare it" do
    g = graph
    seq = Contribution.maximum(:seq)
    trace = Scoring::Score.call(Claim.find(g[:claim].id), seq, v2).trace

    expect(trace["links"].map { |l| l["edition"] }.compact).to be_empty
    expect(trace["links"].map { |l| l["reason"] }).not_to include(Scoring::Calculate::OTHER_EDITION)
  end

  # The rule was released and could not fire: `qualifiers` was stored verbatim,
  # so a bundle naming a source by handle saved the handle where an id belongs;
  # no MCP tool exposed the field at all; and nothing set a lineage. The spec
  # above built its sources by calling create_source directly, which no
  # production path does — a green test that did not imply a working feature
  # (code review, 2026-09-22). This one goes through the write path a person
  # actually uses.
  it "fires for a check recorded the ordinary way" do
    user = User.create!(email_address: "recorder@example.com", password: "correct horse battery staple")
    token = AssistantToken.find_by_token(Assistants::Connect.call(user: user, name: "Claude", provider: "anthropic").last)
    read_at = Time.now.utc.iso8601

    out = Investigations::Record.call(token, {
      "statement" => "What the announcement said when it was published.",
      "sources" => [
        { "handle" => "then", "type" => "WEBSITE", "title" => "The announcement, as published",
          "url" => "https://example.invalid/announcement", "retrieved_at" => read_at },
        { "handle" => "now", "type" => "WEBSITE", "title" => "The announcement, revised",
          "url" => "https://example.invalid/announcement", "retrieved_at" => read_at, "edition_of" => "then" }
      ],
      "excerpts" => [ { "handle" => "x", "source" => "now", "text" => "The revised wording, read later." } ],
      "claims" => [ { "handle" => "c", "text" => "The announcement carried a disclaimer when it was published.",
                      "type" => "TEXTUAL", "qualifiers" => { "source_edition" => "then" } } ],
      "evidence" => [ { "handle" => "e", "excerpt" => "x", "statement" => "The revised page does not carry it.",
                        "observation_type" => "DIRECT_TEXT" } ],
      "links" => [ { "evidence" => "e", "claim" => "c", "direction" => "CONTRADICT", "strength" => "DIRECT", "steps" => 0 } ]
    }, base_url: "http://www.example.com")
    expect(out[:recorded]).to be(true)

    claim = Claim.order(:created_seq).last
    # The handle became an id, and the id is a source that exists.
    edition = claim.qualifiers["source_edition"]
    expect(edition).to match(/\A\h{8}-/), "the handle was stored instead of an id"
    expect(Source.find_by(id: edition)).to be_present
    # The later reading is a version of it, so the rule has a lineage to find.
    later = Source.find_by(previous_version_id: edition)
    expect(later).to be_present

    seq = Contribution.maximum(:seq)
    expect(Scoring::Score.call(Claim.find(claim.id), seq, v3).contradict_groups).to be_zero
    expect(Scoring::Score.call(Claim.find(claim.id), seq, v2).contradict_groups).to eq(1)
  end

  it "ships byte-identical copies of the spec's 0.3.0 configs" do
    spec_dir = Rails.root.join("docs/epistemic-ledger-poc-spec-v4/epistemic-ledger-poc")
    expect(File.binread(Rails.root.join("config/scoring/ledger-default-0.3.0.json")))
      .to eq(File.binread(spec_dir.join("scoring-config-v0.3.json")))
    expect(File.binread(Rails.root.join("config/scoring/ledger-strict-0.3.0.json")))
      .to eq(File.binread(spec_dir.join("scoring-config-strict-v0.3.json")))
  end
end
