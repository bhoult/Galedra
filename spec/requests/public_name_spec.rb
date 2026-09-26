require "rails_helper"

# Sign-up used to register the key under the part of the email address before
# the "@", which put an identifier the person never chose into a signed,
# permanent, public REGISTER_KEY (privacy policy, 2026-09-23).
RSpec.describe "The public name chosen at sign-up", type: :request do
  def sign_up(display_name: nil)
    post "/users", params: { user: { email_address: "jane.q.private@example.com", password: "a long password", password_confirmation: "a long password", display_name: display_name }.compact }
    Contribution.where(action_type: "REGISTER_KEY").order(:seq).last.payload
  end

  it "never publishes any part of the email address" do
    payload = sign_up
    expect(payload.to_json).not_to include("jane")
    expect(payload["display_name"]).to be_nil
  end

  it "publishes the name the person typed, and only that" do
    expect(sign_up(display_name: "  Jane   Q ")["display_name"]).to eq("Jane Q")
  end
end
