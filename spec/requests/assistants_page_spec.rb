require "rails_helper"

RSpec.describe "Connect an assistant page (Stage 12)", type: :request do
  before { release_models }

  it "mints a token signed out and shows it once" do
    get "/assistants/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("anonymous contributor")

    post "/assistants", params: { assistant: { provider: "openai" } }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ChatGPT is connected")
    expect(response.body).to match(/gal_[A-Za-z0-9_-]{20,}/)
    expect(AssistantToken.last.principal).to be_anonymous
  end

  it "lists and disconnects a signed-in user's assistants" do
    user = User.create!(email_address: "me@example.com", password: "correct horse battery staple")
    post session_path, params: { email_address: user.email_address, password: "correct horse battery staple" }
    post "/assistants", params: { assistant: { provider: "anthropic", name: "Desk Claude" } }
    token = AssistantToken.last
    expect(token.user).to eq(user)

    get "/assistants/new"
    expect(response.body).to include("Desk Claude")
    expect(response.body).to include("Disconnect")

    delete "/assistants/#{token.id}"
    expect(response).to redirect_to("/assistants/new")
    expect(token.reload).to be_revoked
    expect(token.delegation.reload).to be_revoked
  end
end
