require "rails_helper"

# Stage 45: an assistant's first reading, recorded at once and shown on the
# check page, never scored, never in a packet, and giving way to evidence.
RSpec.describe "A preliminary result while the sources are read (Stage 45)", type: :request do
  before { release_models }

  let(:token) { Assistants::Connect.call(name: "Claude", provider: "anthropic").last }

  def call_tool(name, arguments, bearer: token)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments } }.to_json,
                 headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{bearer}" }
    [ response.parsed_body.dig("result", "structuredContent"), response.parsed_body.dig("result", "isError") ]
  end

  RATIONALE = "Municipal records usually show narrower rules than viral posts claim."
  LEAD = "https://brackenridge.example/council/minutes/2026-09-03"

  def preliminary(expectation, rationale: RATIONALE)
    { "expectation" => expectation, "rationale" => rationale, "leads" => [ LEAD ], "model" => "claude-opus-5-5" }
  end

  def first_pass
    { "statement" => "Brackenridge banned bicycles downtown, fined forty riders, and the mayor rides a scooter.",
      "on_duplicate" => "create",
      "claims" => [
        { "handle" => "ban", "text" => "Brackenridge has banned bicycles downtown.", "type" => "OBSERVATIONAL", "preliminary" => preliminary("EXPECTED_NOT_TO_HOLD") },
        { "handle" => "fines", "text" => "Brackenridge fined forty cyclists in September 2026.", "type" => "QUANTITATIVE", "preliminary" => preliminary("EXPECTED_TO_HOLD") },
        { "handle" => "mayor", "text" => "The mayor of Brackenridge rides a scooter to work.", "type" => "OBSERVATIONAL", "preliminary" => preliminary("EXPECTED_TO_HOLD") }
      ] }
  end

  # The second pass: a quoted source, linked to one claim.
  def sourced(claim_id, direction)
    { "on_duplicate" => "create",
      "sources" => [ { "handle" => "minutes", "type" => "PRIMARY_TEXT", "title" => "Brackenridge Town Council minutes", "url" => LEAD, "retrieved_at" => Time.now.utc.iso8601 } ],
      "excerpts" => [ { "handle" => "m", "source" => "minutes", "text" => "Motion 14 carried: no fines were issued to cyclists this season." } ],
      "claims" => [ { "handle" => "c", "attach_to" => claim_id } ],
      "evidence" => [ { "handle" => "e", "excerpt" => "m", "statement" => "The minutes record that no fines were issued to cyclists." } ],
      "links" => [ { "evidence" => "e", "claim" => "c", "direction" => direction, "strength" => "DIRECT" } ] }
  end

  it "records three claims with first readings and no sources, and the page leads with them and no badge (acceptance 1 and 7)" do
    data, err = call_tool("record_investigation", first_pass)
    expect(err).to be(false), data.inspect
    expect(PreliminaryResult.count).to eq(3)
    expect(Contribution.where(action_type: "CREATE_PRELIMINARY_RESULT").count).to eq(3)
    expect(data["share"]["preliminary"]).to be(true)
    expect(data["share"]["note"]).to include("offer to find sources")

    lines = data["share_line"].lines(chomp: true)
    expect(lines[0]).to eq("Preliminary (AI, not yet sourced): expected to hold up only in part")
    expect(lines[0]).not_to match(/score|Checked in Galedra/)
    expect(lines[2]).to eq(data["url"])

    get data["url"]
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.css("svg.badge-mark")).to be_empty
    expect(page.css(".preliminary-stamp").size).to eq(4)
    expect(page.css(".preliminary").size).to eq(3)
    expect(response.body).to include("Of these 3 parts, an assistant expects 2 to hold up and 1 not to hold up.")
    expect(response.body).to include("claude-opus-5-5, as declared").and include(RATIONALE).and include("Galedra has not read them")
    expect(page.at_css('meta[property="og:title"]')["content"]).to eq(lines[0])

    stamped = []
    allow(Cards::Image).to receive(:stamp).and_wrap_original { |m, canvas, text, *rest| stamped << text; m.call(canvas, text, *rest) }
    get "#{data['url']}/card.png"
    expect(response).to have_http_status(:ok)
    expect(stamped.first).to include("PRELIMINARY")
    expect(stamped).to include("Preliminary: expected to hold up only in part")
    expect(stamped.join(" ")).not_to match(/Nobody has checked|score/)
  end

  it "moves a claim's reading beneath its own state once evidence counts, and says when the two disagree (acceptance 2)" do
    data, = call_tool("record_investigation", first_pass)
    url = data["url"]
    fines = data["claims"].find { |c| c["handle"] == "fines" }["id"]
    contra, err = call_tool("record_investigation", sourced(fines, "CONTRADICT"))
    expect(err).to be(false), contra.inspect

    get url
    page = Nokogiri::HTML(response.body)
    # One claim has a state from evidence, so the check is no longer
    # preliminary: the top card has its badge again, and so does that claim.
    # The two unsourced claims still lead with their reading.
    expect(page.css("svg.badge-mark").size).to eq(2)
    expect(page.css(".preliminary").size).to eq(2)
    beneath = page.css(".preliminary-beneath summary").map(&:text)
    expect(beneath.join).to include("The first reading expected this to hold up; the sources so far lean against it.")
    expect(page.at_css(".share-line").text).to start_with("Checked in Galedra:")
    expect(response.body).not_to include("Preliminary (AI, not yet sourced)")
  end

  it "never moves a score: the same inputs give byte-identical traces under every model (acceptance 3)" do
    data, = call_tool("record_investigation", first_pass.merge("claims" => first_pass["claims"].map { |c| c.except("preliminary") }))
    claim = Claim.find(data["claims"].first["id"])
    before_seq = Contribution.maximum(:seq)
    before = Scoring::BuildInput.call(claim, before_seq)
    append_preliminary = Assistants::Write.call(AssistantToken.find_by_token(token), "CREATE_PRELIMINARY_RESULT",
                                                { "claim_id" => claim.id, "expectation" => "EXPECTED_NOT_TO_HOLD", "rationale" => RATIONALE, "leads" => [ LEAD ] })
    after_seq = append_preliminary.contribution.seq
    expect(after_seq).to be > before_seq
    after = Scoring::BuildInput.call(claim, after_seq).merge("snapshot_seq" => before_seq)
    expect(after).to eq(before)
    expect(ScoringModel.count).to be >= 2
    ScoringModel.find_each do |model|
      trace = ->(input) { Scoring::Calculate.call(input, config: model.config, model: model.full_name, code_hash: model.code_hash).trace_hash }
      expect(trace.call(after)).to eq(trace.call(before))
    end
    expect(claim.reload.scored_inputs_seq).to be < after_seq # the watermark did not move: nothing a score reads changed
  end

  it "keeps the reading out of every task packet (acceptance 4)" do
    data, = call_tool("record_investigation", first_pass)
    claim = Claim.find(data["claims"].first["id"])
    contra, = call_tool("record_investigation", sourced(claim.id, "SUPPORT"))
    expect(contra["recorded"]).to be(true)
    location = SourceLocation.order(:created_seq).last
    seq = Contribution.maximum(:seq)
    types = Tasks::Types::SPECS.select { |_, spec| spec[:target_type] == "CLAIM" }.keys
    expect(types).to include("EVIDENCE_VERIFICATION", "OPPOSING_EVIDENCE_SEARCH", "QUALIFIER_CHECK", "SOURCE_INDEPENDENCE_CHECK")
    types.each do |type|
      packet = Tasks::BuildContext.call(task_type: type, target_id: claim.id, snapshot_seq: seq, location_id: location.id).to_json
      expect(packet).not_to include(RATIONALE)
      expect(packet).not_to include(LEAD)
      PreliminaryResult::EXPECTATIONS.each { |word| expect(packet).not_to include(word) }
    end
  end

  it "refuses a reading on an outline's claim or a NORMATIVE claim, naming the field and the remedy (acceptance 5)" do
    normative = first_pass.merge("claims" => [ { "handle" => "n", "text" => "Brackenridge should allow bicycles downtown.", "type" => "NORMATIVE", "preliminary" => preliminary("EXPECTED_TO_HOLD") } ])
    data, err = call_tool("record_investigation", normative)
    expect(err).to be(true)
    expect(data["errors"].first).to include("path" => "$.claims[0].preliminary")
    expect(data["errors"].first["detail"]).to include("NORMATIVE").and include("leave preliminary off")

    outline, err = call_tool("create_outline", { "statement" => "A council meeting", "source" => { "type" => "VIDEO", "title" => "Council meeting", "url" => "https://example.org/meeting", "retrieved_at" => Time.now.utc.iso8601 },
                                                 "sections" => [ { "handle" => "root", "heading" => "The meeting", "sections" => [
                                                   { "handle" => "leaf", "heading" => "Opening", "locator" => { "type" => "TIME_RANGE", "start" => "00:00:00", "end" => "00:04:00" },
                                                     "anchor" => "The meeting opened at seven.", "reading" => "The meeting opened at seven." } ] } ] })
    expect(err).to be(false), outline.inspect
    leaf = outline["sections"]["leaf"]["id"]
    sectioned = { "claims" => [ { "handle" => "s", "text" => "The council meeting opened at seven.", "type" => "OBSERVATIONAL", "section" => leaf, "preliminary" => preliminary("EXPECTED_TO_HOLD") } ], "on_duplicate" => "create" }
    data, err = call_tool("record_investigation", sectioned)
    expect(err).to be(true)
    expect(data["errors"].first).to include("path" => "$.claims[0].preliminary")
    expect(data["errors"].first["detail"]).to include("outline").and include("record the claim's evidence instead")
    expect(PreliminaryResult.count).to eq(0)

    # The applier holds the same rule for a direct write.
    call_tool("record_investigation", sectioned.merge("claims" => [ sectioned["claims"].first.except("preliminary") ]))
    claim = Claim.find_by!(canonical_text: "The council meeting opened at seven.")
    expect {
      Assistants::Write.call(AssistantToken.find_by_token(token), "CREATE_PRELIMINARY_RESULT", { "claim_id" => claim.id, "expectation" => "EXPECTED_TO_HOLD", "rationale" => RATIONALE })
    }.to raise_error(Ledger::Rejected) { |e| expect(e.errors.first[:code]).to eq("PRELIMINARY_NOT_FOR_OUTLINES") }
  end

  it "is reproduced by replay row for row, and can be taken down (acceptance 6)" do
    call_tool("record_investigation", first_pass)
    before = Ledger::TableDigest.table(PreliminaryResult)
    all = Ledger::TableDigest.projections
    Ledger::Replay.call
    expect(Ledger::TableDigest.table(PreliminaryResult)).to eq(before)
    expect(Ledger::TableDigest.projections).to eq(all)

    moderator = register_moderator.first
    target = Contribution.where(action_type: "CREATE_PRELIMINARY_RESULT").in_order.first
    td = takedown(moderator, target)
    row = PreliminaryResult.find_by!(contribution_id: target.id)
    expect(row).to have_attributes(rationale: nil, leads: [], model: nil, redacted_by_seq: td.seq)
    get "/investigations/#{Investigation.last.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("This first reading was taken down")
    # Its expectation survives redaction but is not repeated: the share line
    # and the og title read the two readings still standing, not the removed
    # "not to hold up" that made the whole "only in part".
    page = Nokogiri::HTML(response.body)
    expect(page.at_css(".share-line").text).to start_with("Preliminary (AI, not yet sourced): expected to hold up\n")
    expect(page.at_css('meta[property="og:title"]')["content"]).to eq("Preliminary (AI, not yet sourced): expected to hold up")
    expect(response.body).not_to include("1 not to hold up")
  end

  it "loads who recorded each reading once for the page, not once per claim" do
    count = lambda do |claims|
      bundle = first_pass.merge("statement" => "#{claims} parts", "claims" => Array.new(claims) { |i| { "handle" => "c#{i}", "text" => "Brackenridge part #{i} of #{claims} holds.", "type" => "OBSERVATIONAL", "preliminary" => preliminary("EXPECTED_TO_HOLD") } })
      data, err = call_tool("record_investigation", bundle)
      expect(err).to be(false), data.inspect
      n = 0
      counter = ->(*, payload) { n += 1 if payload[:sql].to_s.match?(/FROM "contributors"/) }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get data["url"] }
      expect(response.body).to include("Recorded by")
      n
    end
    expect(count.call(5)).to eq(count.call(2))
  end

  it "refuses an overlong lead under the bundle's own path, as the applier would" do
    long = "https://example.org/#{'a' * PreliminaryResult::MAX_LEAD_CHARS}"
    bundle = first_pass.merge("claims" => [ first_pass["claims"].first.merge("preliminary" => preliminary("EXPECTED_TO_HOLD").merge("leads" => [ long ])) ])
    data, err = call_tool("record_investigation", bundle)
    expect(err).to be(true)
    expect(data["errors"].first).to include("path" => "$.claims[0].preliminary.leads")
    expect(PreliminaryResult.count).to eq(0)
  end

  it "says what one part said, whatever the parts with no expectation beside it" do
    expect(Investigations::Preliminary.phrase(%w[EXPECTED_TO_HOLD_IN_PART])).to eq("expected to hold up in part")
    expect(Investigations::Preliminary.phrase(%w[EXPECTED_TO_HOLD_IN_PART NO_EXPECTATION])).to eq("expected to hold up in part")
    expect(Investigations::Preliminary.phrase(%w[EXPECTED_TO_HOLD EXPECTED_NOT_TO_HOLD NO_EXPECTATION])).to eq("expected to hold up only in part")
  end

  it "shows each check only its own reading on a shared claim, and the claim page shows both (acceptance 8)" do
    first, = call_tool("record_investigation", first_pass)
    shared = first["claims"].find { |c| c["handle"] == "mayor" }["id"]
    second, err = call_tool("record_investigation", { "statement" => "The mayor rides a scooter.",
                                                      "claims" => [ { "handle" => "m", "attach_to" => shared, "preliminary" => preliminary("NO_EXPECTATION", rationale: "No record either way that I know of.") } ] })
    expect(err).to be(false), second.inspect
    expect(second["share_line"].lines.first.chomp).to eq("Preliminary (AI, not yet sourced): no expectation either way")

    get first["url"]
    expect(response.body).to include(RATIONALE)
    expect(response.body).not_to include("No record either way that I know of.")
    get second["url"]
    expect(response.body).to include("No record either way that I know of.")
    expect(response.body).not_to include(RATIONALE)
    get "/claims/#{shared}"
    expect(response.body).to include("Preliminary readings").and include(RATIONALE).and include("No record either way that I know of.")
  end

  it "tells the assistant to end its turn after the first pass and offer to source each claim (acceptance 9)" do
    expect(Guidance::END_TURN).to start_with("Then end your turn: give the person the share_line and offer to find sources for each claim.")
    expect(Guidance.for(:check)).to include(Guidance::END_TURN)
    expect(Guidance::SIZE).not_to include("read every source")
    get "/api/v1/guidance", params: { topic: "check" }
    expect(response.body).to include("offer to find sources for each claim")
  end
end
