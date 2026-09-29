require "rails_helper"

# Search the text an investigation or outline holds (owner request,
# 2026-09-29). The claims list searched claim text only, so a phrase remembered
# from a section's reading, a statement, or a quotation had nowhere to go.
RSpec.describe "Search", type: :request do
  before { release_models }

  let(:pair) { register_key.first }
  let(:token) { AssistantToken.find_by_token(Assistants::Connect.call(name: "Checker", provider: "other").last) }

  def investigation(statement, claim_ids)
    Investigation.create!(id: SecureRandom.uuid_v7, assistant_token: token, statement: statement, claim_ids: claim_ids, snapshot_seq: Contribution.maximum(:seq))
  end

  def statements
    n = 0
    counter = ->(*, payload) { n += 1 unless payload[:name].to_s == "SCHEMA" || payload[:sql].to_s.start_with?("BEGIN", "COMMIT") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    n
  end

  def outline_with_reading(heading, reading_text)
    source = create_source(pair, title: "#{heading} transcript", content: "#{reading_text} And then something else entirely.")
    reading = create_location(pair, source, start: 0, finish: reading_text.length, locator_type: "TRANSCRIPTION", locator: { "start" => "00:00:00", "end" => "00:01:00" })
    result = append(action_type: "CREATE_SECTION", key_pair: pair, payload: { "source_id" => source.id, "sections" => [
      { "heading" => "#{heading} episode", "sections" => [ { "heading" => heading, "reading_location_id" => reading.id } ] } ] })
    Section.where(contribution_id: result.contribution.id).order(:depth).to_a
  end

  it "finds a section by its reading, a statement, a claim and a quoted passage" do
    root, leaf = outline_with_reading("Harbour dredging", "The council voted to dredge the harbour before the regatta.")
    claim = create_claim(pair, "The regatta moved to the north basin this year.", type: "OBSERVATIONAL")
    investigation("Did the regatta really move basins?", [ claim.id ])
    source = create_source(pair, title: "Harbour notice", content: "Notice: the regatta course is closed for dredging works.")
    passage = create_location(pair, source)
    link_evidence(pair, create_evidence(pair, passage, statement: "The notice says the course is closed."), claim)

    get search_path(q: "regatta")
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include(section_path(leaf)), "a section found by the text it reads"
    expect(body).to include("in #{root.heading}").or include(root.heading)
    expect(body).to include("Did the <mark>regatta</mark> really move basins?")
    expect(body).to include(claim_path(claim))
    expect(body).to include("the <mark>regatta</mark> course is closed")

    get search_path(q: "\"dredge the harbour\"")
    expect(response.body).to include(section_path(leaf)), "a quoted phrase matches as a phrase"
    get search_path(q: "\"harbour the dredge\"")
    expect(response.body).not_to include(section_path(leaf))
  end

  it "searches nothing withheld by moderation" do
    moderator, = register_moderator
    hidden = create_claim(pair, "A private person named in a rumour about the lighthouse.", type: "OBSERVATIONAL")
    quarantine(moderator, hidden)
    source = create_source(pair, title: "Lighthouse gossip", content: "Everyone says the lighthouse keeper sold the lamp.")
    create_location(pair, source)
    quarantine(moderator, source)
    investigation("A rumour about the lighthouse and a private person", [ hidden.id ])

    get search_path(q: "lighthouse")
    expect(response.body).not_to include(claim_path(hidden))
    expect(response.body).not_to include("keeper sold the lamp")
    expect(response.body).not_to include("private person"), "a statement whose every claim is withheld is withheld too"
  end

  # Postgres's snippet drops anything shaped like a tag, and everything else is
  # escaped before the match markers become <mark>.
  it "shows stored text as text, never as markup" do
    source = create_source(pair, title: "Odd page", content: "At the beacon the tide rose 5 < 6 & 7 > 3 feet, <script>alert(1)</script> it says.")
    create_location(pair, source)
    get search_path(q: "beacon")
    expect(response.body).to include("5 &lt; 6 &amp; 7 &gt; 3")
    expect(response.body).not_to include("<script>alert(1)</script>")
  end

  it "asks the same number of statements however many things match" do
    # One of each kind first, so both searches take every branch; what must not
    # grow is the cost per match.
    claim = create_claim(pair, "One claim about ferries.", type: "OBSERVATIONAL")
    outline_with_reading("Ferry timetable", "The ferries were cancelled on Tuesday.")
    investigation("Were the ferries cancelled?", [ claim.id ])
    link_evidence(pair, create_evidence(pair, create_location(pair, create_source(pair, title: "Ferry notice", content: "All ferries suspended."))), claim)
    one = statements { get search_path(q: "ferries") }
    5.times { |i| create_claim(pair, "Another claim about ferries, number #{i}.", type: "OBSERVATIONAL") }
    3.times { |i| outline_with_reading("Ferry route #{i}", "The ferries ran late on route #{i} all week.") }
    3.times { |i| investigation("Did the ferries run on day #{i}?", [ claim.id ]) }
    3.times { |i| link_evidence(pair, create_evidence(pair, create_location(pair, create_source(pair, title: "Notice #{i}", content: "Ferries delayed, notice #{i}."))), claim) }
    many = statements { get search_path(q: "ferries") }
    expect(many).to eq(one)
  end

  it "refuses a query longer than a few words would need" do
    get search_path(q: "word " * 100)
    expect(response.body).to include("at most #{Search::Text::MAX_QUERY_CHARS} characters")
  end
end
