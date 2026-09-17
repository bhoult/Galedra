require "rails_helper"

RSpec.describe "GET /", type: :request do
  it "renders the home page without authentication" do
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Galedra")
    expect(response.body).to include(Governance::Constitution.new.digest)
  end
end
