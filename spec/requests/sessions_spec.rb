require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let(:password) { "correct horse battery staple" }
  let!(:user) { User.create!(email_address: "reader@example.com", password: password) }

  it "sends a signed-out visitor to sign in and returns them afterwards" do
    get "/analyze/new"
    expect(response).to redirect_to("/session/new")

    post "/session", params: { email_address: user.email_address, password: password }
    expect(response).to redirect_to("http://www.example.com/analyze/new")
    follow_redirect!
    expect(response.body).to include("Analyze text")
  end

  it "refuses a wrong password and signs out with a redirect" do
    post "/session", params: { email_address: user.email_address, password: "wrong" }
    expect(response).to redirect_to("/session/new")
    expect(flash[:alert]).to include("Try another")

    post "/session", params: { email_address: user.email_address, password: password }
    delete "/session"
    expect(response).to have_http_status(:see_other)
    get "/analyze/new"
    expect(response).to redirect_to("/session/new")
  end

  it "signs up with a server-custodied key and rejects a mismatched confirmation" do
    post "/users", params: { user: { email_address: "new@example.com", password: password, password_confirmation: "different" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Password confirmation")

    post "/users", params: { user: { email_address: "new@example.com", password: password, password_confirmation: password } }
    expect(response).to redirect_to("/")
    expect(User.find_by!(email_address: "new@example.com").custodied_key.contributor.display_name).to eq("new")
  end
end
