require "rails_helper"

RSpec.describe "Admin users (Stage 24)", type: :request do
  let(:password) { "correct horse battery staple" }

  def sign_up(email)
    post "/users", params: { user: { email_address: email, password: password, password_confirmation: password } }
    User.find_by!(email_address: email)
  end

  def sign_in(user)
    post "/session", params: { email_address: user.email_address, password: password }
  end

  it "makes the first account an admin and no later one" do
    first = sign_up("first@example.com")
    expect(first).to be_admin
    expect(first.admin_granted_at).to be_present
    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to include("first account")

    delete "/session"
    second = sign_up("second@example.com")
    expect(second).not_to be_admin
  end

  # The queue an admin is responsible for, in the bar they are already looking
  # at (owner request, 2026-09-20).
  it "badges open bug reports and feature requests for an admin, and for nobody else" do
    admin = sign_up("first@example.com")
    BugReport.record!(happened: "The share card renders blank", expected: "an image")
    BugReport.record!(happened: "The outline page is truncated", expected: "the whole tree")
    answered = BugReport.record!(happened: "Something else", expected: "something").first
    answered.answer!(body: "Fixed.", user: admin)
    raw = Assistants::Connect.call(user: admin, name: "Claude", provider: "anthropic").last
    FeatureRequest.record!(asked: "list claims by source", needed: "a filter", token: AssistantToken.find_by_token(raw))

    get "/"
    expect(response.body).to match(%r{<span class="report-badge"})
    expect(response.body).to include("2 bug reports waiting on a maintainer")
    expect(response.body).to include("1 feature request waiting on a maintainer"), "answered is the filer's turn, not ours"
    expect(response.body).to include(bug_reports_path(status: "OPEN"))
    expect(response.body).not_to include("held open"), "nothing is held, so the mark is absent rather than zero"

    # Held rides beside its own type, and is not added to the number you clear.
    BugReport.record!(happened: "A quoted passage reads as not found", expected: "it confirmed").first
             .answer!(body: "Agreed; it needs a stage.", user: admin, settles: false)
    get "/"
    expect(response.body).to include("2 bug reports waiting on a maintainer"), "held is not open"
    expect(response.body).to include("1 bug report answered and held open")
    expect(response.body).to include(bug_reports_path(status: "HELD"))

    delete "/session"
    other = sign_up("second@example.com")
    get "/"
    expect(response.body).not_to include("report-badge")
    expect(other).not_to be_admin
  end

  it "shows the Admin menu only to admins and refuses the page to others" do
    admin = sign_up("first@example.com")
    get "/"
    expect(response.body).to match(%r{<summary[^>]*>Admin</summary>})
    expect(response.body).to include(">Help<")
    get "/admin/users"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin.email_address)

    delete "/session"
    other = sign_up("second@example.com")
    get "/"
    expect(response.body).not_to match(%r{<summary[^>]*>Admin</summary>})
    get "/admin/users"
    expect(response).to redirect_to(root_path)
    post "/admin/users/#{admin.id}/revoke_admin"
    expect(response).to redirect_to(root_path)
    expect(admin.reload).to be_admin
    expect(other.reload).not_to be_admin
  end

  it "lets an admin grant and revoke admin and moderator, but never revoke the last admin" do
    admin = sign_up("first@example.com")
    delete "/session"
    other = sign_up("second@example.com")
    delete "/session"
    sign_in(admin)

    post "/admin/users/#{admin.id}/revoke_admin"
    expect(flash[:alert]).to include("last admin")
    expect(admin.reload).to be_admin

    post "/admin/users/#{other.id}/grant_admin"
    expect(other.reload).to be_admin
    expect(other.admin_granted_by).to eq(admin)

    post "/admin/users/#{other.id}/grant_moderator"
    expect(other.reload).to be_moderator
    expect(Governance::Moderators.key_ids).to include(other.contributor.key_id)
    get "/api/v1/meta"
    expect(response.parsed_body["moderator_key_ids"]).to include(other.contributor.key_id)

    post "/admin/users/#{other.id}/revoke_moderator"
    expect(other.reload).not_to be_moderator

    post "/admin/users/#{admin.id}/revoke_admin"
    expect(admin.reload).not_to be_admin
    expect(User.admins.count).to eq(1)
  end

  it "opens feature requests to admins as well as moderators" do
    sign_up("first@example.com")
    get "/feature_requests"
    expect(response).to have_http_status(:ok)
  end
end
