require "rails_helper"

# An outline and a check are different questions. An outline is a long source
# worked through section by section — a speech, a transcript, a podcast. A check
# is short: a meme, a quotation, a figure somebody sent you. Both create an
# Investigation row, so the checks list carried both, and a quarter of its rows
# redirected the reader into /sections the moment they were clicked (owner,
# 2026-09-22).
RSpec.describe "Checks and outlines are different lists", type: :request do
  include GraphHelpers
  before { release_models }

  let(:user) { User.create!(email_address: "me@example.com", password: "correct horse battery staple") }
  let(:token) { AssistantToken.find_by_token(Assistants::Connect.call(user: user, name: "Claude", provider: "anthropic").last) }

  it "lists short checks and leaves outlines to their own page" do
    Investigations::Record.call(token, { "statement" => "A short statement someone sent me.",
                                         "claims" => [ { "handle" => "c", "text" => "A checkable claim from a meme.", "type" => "TEXTUAL" } ] },
                                base_url: "http://www.example.com")
    check = Investigation.order(:created_at).last

    pair, = register_key
    source = create_source(pair, title: "A transcript", content: "A sentence of it. " * 20)
    result = append(action_type: "CREATE_SECTION", key_pair: pair,
                    payload: { "source_id" => source.id, "sections" => [ { "heading" => "The whole thing" } ] })
    section = Section.find(Ledger::Ids.derive(result.contribution.id, "section", 0))
    outline = Investigation.create!(assistant_token: token, section_id: section.id, statement: "A podcast worked through",
                                    claim_ids: [], snapshot_seq: Contribution.maximum(:seq))

    get "/investigations"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(check.id)
    expect(response.body).not_to include(outline.id), "an outline is not a check and has its own list"
    expect(response.body).to include("outline"), "and the page says where the other kind lives"
  end

  # The redirect stays: a link handed out before this still has to work.
  it "still takes an old outline link to the outline" do
    pair, = register_key
    source = create_source(pair, title: "A transcript", content: "A sentence of it. " * 20)
    result = append(action_type: "CREATE_SECTION", key_pair: pair,
                    payload: { "source_id" => source.id, "sections" => [ { "heading" => "The whole thing" } ] })
    section = Section.find(Ledger::Ids.derive(result.contribution.id, "section", 0))
    outline = Investigation.create!(assistant_token: token, section_id: section.id, statement: "A podcast",
                                    claim_ids: [], snapshot_seq: Contribution.maximum(:seq))

    get "/investigations/#{outline.id}"
    expect(response).to redirect_to(section_path(section.id))
  end
end
