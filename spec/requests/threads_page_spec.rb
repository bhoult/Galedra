require "rails_helper"

RSpec.describe "Threads in the interface (Stage 37)", type: :request do
  include GraphHelpers
  before { release_models }

  let(:password) { "correct horse battery staple" }
  let(:curator) { register_key(display_name: "Curator").first }
  let(:claim) { create_claim(curator, "Remote work raises productivity.", type: "CAUSAL") }
  let(:thread) { DeterminationThread.record!(subject: claim, concern: "The figures are not in the passage it rests on.").first }

  def sign_up(email, admin: false)
    post "/users", params: { user: { email_address: email, password: password, password_confirmation: password } }
    User.find_by!(email_address: email).tap { |u| u.update!(admin: admin) }
  end

  it "lists every thread on the node and links each to what it hangs on" do
    thread
    get "/threads"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("The figures are not in the passage")
    expect(response.body).to include(claim.canonical_text[0, 40])
    expect(response.body).to include(thread_path(thread))
    expect(response.body).to include("does not determine it")
  end

  it "shows an anonymous visitor the thread and no reply form" do
    thread
    get "/threads/#{thread.id}"
    expect(response.body).to include("The figures are not in the passage")
    expect(response.body).not_to include("Say this")
    expect(response.body).to include("has to belong to somebody")
  end

  # A person's turn counts as their principal, which is also why their own
  # assistant's turn is the same principal and does not count twice.
  it "lets a signed-in person take a turn and vote" do
    user = sign_up("me@example.com")
    post "/session", params: { email_address: user.email_address, password: password }
    post "/threads/#{thread.id}/respond", params: { body: "I read the source; the figures are absent from the quote.", verdict: "INVESTIGATE" }
    expect(flash[:notice]).to include("Your vote is counted")
    expect(thread.reload.tally).to eq("INVESTIGATE" => 1)
    expect(thread.turns.last.user_id).to eq(user.id)

    get "/threads/#{thread.id}"
    expect(response.body).to include("1</strong> for investigate")
  end

  # The escape a node with too few principals needs, and the page says which.
  it "lets an admin settle one by hand" do
    admin = sign_up("first@example.com", admin: true)
    post "/session", params: { email_address: admin.email_address, password: password }
    post "/admin/threads/#{thread.id}/settle", params: { outcome: "NO_FURTHER_WORK" }
    expect(thread.reload).to be_settled
    expect(thread.outcome).to eq("NO_FURTHER_WORK")

    get "/threads/#{thread.id}"
    expect(response.body).to include("Settled as no further work")
  end

  it "shows a claim's threads on the claim, and lets a signed-in person open one there" do
    thread
    get "/claims/#{claim.id}"
    expect(response.body).to include("The figures are not in the passage")
    expect(response.body).to include("moves no probability")

    user = sign_up("me@example.com")
    post "/session", params: { email_address: user.email_address, password: password }
    post "/threads", params: { subject_type: "Claim", subject_id: claim.id, concern: "These two items answer different survey questions and the card does not say so." }
    opened = DeterminationThread.newest_first.first
    expect(opened.subject_id).to eq(claim.id)
    expect(opened.user_id).to eq(user.id)
    expect(response).to redirect_to(thread_path(opened))
  end

  it "refuses a settle from someone who is not an admin" do
    user = sign_up("first@example.com", admin: true)
    delete "/session"
    other = sign_up("second@example.com")
    post "/session", params: { email_address: other.email_address, password: password }
    post "/admin/threads/#{thread.id}/settle", params: { outcome: "NO_FURTHER_WORK" }
    expect(thread.reload).to be_open
    expect(user).to be_admin
  end
end
