require "rails_helper"

# Everything shown here was already in the log — the signing key, the person it
# acted for, the entry itself — and no page showed it, so a reader had no way to
# ask "who did this?" without going to the log and working it out (owner request,
# 2026-09-21).
RSpec.describe "Who initiated a piece of work", type: :request do
  include GraphHelpers
  before { release_models }

  let(:password) { "correct horse battery staple" }
  let(:user) { User.create!(email_address: "me@example.com", password: password) }
  let(:token) { AssistantToken.find_by_token(Assistants::Connect.call(user: user, name: "Claude", provider: "anthropic").last) }

  def record(bundle) = Investigations::Record.call(token, bundle, base_url: "http://www.example.com")

  it "names the key that signed an investigation and the person it acted for" do
    out = record("statement" => "A statement to check.",
                 "claims" => [ { "handle" => "c", "text" => "A claim recorded through a connector.", "type" => "TEXTUAL" } ])
    investigation = Investigation.order(:created_at).last
    expect(out[:recorded]).to be(true)

    get "/investigations/#{investigation.id}"
    expect(response.body).to include("Recorded by")
    expect(response.body).to include(short_id_of(token.agent.key_id))
    expect(response.body).to include(user.email_address.split("@").first).or include(token.principal.display_name.to_s)
    expect(response.body).to include("open to audit")
  end

  it "attributes an outline to whoever recorded its root, not its latest child" do
    pair, = register_key(display_name: "Curator")
    source = create_source(pair, title: "A transcript", content: "Opening. #{'word ' * 30}")
    result = append(action_type: "CREATE_SECTION", key_pair: pair,
                    payload: { "source_id" => source.id, "sections" => [
                      { "heading" => "Chapter one", "sections" => [ { "heading" => "A part of it" } ] } ] })
    root = Section.find(Ledger::Ids.derive(result.contribution.id, "section", 0))

    # Somebody else fills in a part of it later. The outline is still the first
    # one's; the page must not hand it to whoever touched it last.
    other, = register_key(Crypto::Ed25519::KeyPair.generate, display_name: "A later hand")
    later = append(action_type: "CREATE_SECTION", key_pair: other,
                   payload: { "parent_section_id" => root.id, "sections" => [ { "heading" => "A part of it" } ] })
    child = Section.find(Ledger::Ids.derive(later.contribution.id, "section", 0))

    # Reading a section deep in an outline still names who started the outline,
    # and links the entry in the log it came from.
    get "/sections/#{child.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Recorded by")
    expect(response.body).to include(short_id_of(root.contribution.contributor.key_id))
    expect(response.body).not_to include(short_id_of(child.contribution.contributor.key_id))
    expect(response.body).to include("the entry in the log")

    # The later hand is not lost, it is on the page that lists everyone.
    get "/sections/#{child.id}/contributors"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(short_id_of(root.contribution.contributor.key_id))
                        .and include(short_id_of(child.contribution.contributor.key_id))
    expect(response.body).to include("outlined the source")
  end

  # The foot of a check names whoever started it; that is the smaller half of the
  # answer, because a check is usually filled in by other keys afterwards
  # (owner request, 2026-09-21).
  it "lists every key that went into a check, and who each one signed for" do
    record("statement" => "A statement to check.",
           "claims" => [ { "handle" => "c", "text" => "A claim somebody else will find evidence for.", "type" => "TEXTUAL" } ])
    investigation = Investigation.order(:created_at).last
    claim = investigation.claims.first

    # A second key reads a source and attaches what it found.
    later, = register_key(Crypto::Ed25519::KeyPair.generate, display_name: "A later hand")
    source = create_source(later, title: "A report")
    link_evidence(later, create_evidence(later, create_location(later, source)), claim)

    get "/investigations/#{investigation.id}"
    expect(response.body).to include("everyone who contributed")

    get "/investigations/#{investigation.id}/contributors"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(short_id_of(token.agent.key_id)).and include(short_id_of(later.key_id))
    expect(response.body).to include("wrote a claim").and include("linked evidence to a claim")
    # An agent is shown with the person it signed for; a human signs for itself.
    expect(response.body).to include(user.email_address.split("@").first).or include(token.principal.display_name.to_s)
    expect(response.body).to include("itself")
  end

  # The gather asks each table once for the whole set. One query per claim is the
  # defect this codebase keeps producing (CLAUDE.md), so the number is pinned
  # here: 20 statements for 24 claims, and the same 20 for eight of them.
  #
  # Raised from 18 on 2026-09-22, deliberately: the header now carries a model
  # picker on every page, which costs one statement for the released models and
  # one for the node's default. Two for a control on every page is a real price
  # and it is recorded here rather than absorbed — if it grows again, something
  # is wrong with the header, not with this page.
  it "counts the whole set in a bounded number of statements" do
    pair, = register_key(display_name: "Curator")
    source = create_source(pair, title: "A report")
    location = create_location(pair, source)
    claims = Array.new(24) { |i| create_claim(pair, "A checkable claim, number #{i}.") }
    claims.each { |c| link_evidence(pair, create_evidence(pair, location), c) }
    investigation = Investigation.create!(assistant_token: token, statement: "Eight claims.", claim_ids: claims.map(&:id),
                                         snapshot_seq: Contribution.maximum(:seq))

    n = 0
    counter = ->(*, payload) { n += 1 unless payload[:name].to_s == "SCHEMA" || payload[:sql].to_s.start_with?("BEGIN", "COMMIT") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get "/investigations/#{investigation.id}/contributors" }
    expect(response).to have_http_status(:ok)
    expect(n).to be <= 20, "#{n} statements for #{claims.size} claims"
  end

  # One partial, so the two pages cannot drift into saying different things about
  # the same fact.
  it "renders both from the same partial" do
    views = Dir[Rails.root.join("app/views/**/*.erb")].select { |f| File.read(f).include?("attribution") }
    rendered = views.map { |f| f.sub("#{Rails.root}/", "") }
    expect(rendered).to include("app/views/shared/_attribution.html.erb")
    others = rendered - [ "app/views/shared/_attribution.html.erb" ]
    others.each do |f|
      expect(File.read(Rails.root.join(f))).to include('render "shared/attribution"'),
                                               "#{f} mentions attribution without using the shared partial"
    end
  end

  def short_id_of(id) = id.to_s.length > 8 ? id.to_s[-8..] : id.to_s
end
