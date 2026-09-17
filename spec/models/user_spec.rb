require "rails_helper"

RSpec.describe User, type: :model do
  it "normalizes the email address" do
    user = create(:user, email_address: "  Curator@Example.COM ")
    expect(user.email_address).to eq("curator@example.com")
  end

  it "authenticates with the secure password" do
    user = create(:user, password: "correct horse battery staple")
    expect(user.authenticate("correct horse battery staple")).to eq(user)
    expect(user.authenticate("wrong")).to be_falsey
  end
end
