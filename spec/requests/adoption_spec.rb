require "rails_helper"

RSpec.describe "Adopting anonymous work (after Stage 14)", type: :request do
  before { release_models }

  def bundle
    JSON.parse(File.read(Rails.root.join("examples/agent/investigation.json"))).except("_about").tap do |b|
      b["sources"].each { |s| s["retrieved_at"] = "2026-09-18T12:00:00Z" }
    end
  end

  it "offers an adoption link on anonymous work and puts it under an account through a signed ADOPT_KEY" do
    post "/api/v1/investigations", params: bundle.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    expect(response).to have_http_status(:created)
    attribution = response.parsed_body["attribution"]
    expect(attribution["anonymous"]).to be(true)
    expect(attribution["adopt_url"]).to match(%r{\Ahttp://www.example.com/adopt/adopt_[A-Za-z0-9_-]+\z})
    code = attribution["adopt_url"].split("/").last
    ban = response.parsed_body["claims"].first
    anonymous_key = Claim.find(ban["id"]).contribution.principal_contributor
    expect(anonymous_key).to be_anonymous

    get "/adopt/#{code}"
    expect(response).to redirect_to("/session/new")
    user = User.create!(email_address: "me@example.com", password: "correct horse battery staple")
    post session_path, params: { email_address: user.email_address, password: "correct horse battery staple" }
    expect(response).to redirect_to("http://www.example.com/adopt/#{code}")

    get "/adopt/#{code}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Put this under my name")
    expect(response.body).to include("Ashcombe has banned bicycles downtown.").or include("Brackenridge has banned bicycles downtown.")

    post "/adopt/#{code}"
    expect(response).to redirect_to(contributor_path(anonymous_key))
    adoption = Contribution.find_by!(action_type: "ADOPT_KEY")
    adopter = user.reload.custodied_key.contributor
    expect(adoption.signer_key_id).to eq(adopter.key_id)
    expect(adoption.custody).to eq("SERVER")
    expect(anonymous_key.reload).not_to be_anonymous
    expect(anonymous_key.adopted_by_key_id).to eq(adopter.key_id)
    expect(anonymous_key.identity_tier).to eq("PSEUDONYMOUS")
    expect(Ledger::Verify.call.status).to eq("CHAIN_VERIFIED")

    get contributor_path(anonymous_key)
    expect(response.body).to include("adopted at seq #{adoption.seq}")
    get contributor_path(adopter)
    expect(response.body).to include("Also stands behind")

    seq = Contribution.maximum(:seq)
    card = Cards::ClaimCard.call(Claim.find(ban["id"]), seq, Scoring::Registry.default_model)
    expect(card[:labels]).to include("Not yet independently audited.")
    expect(card[:labels]).not_to include(a_string_including("anonymous contributor"))

    post "/adopt/#{code}"
    expect(response).to redirect_to("/adopt/#{code}")
    follow_redirect!
    expect(response.body).to include("already under an account")

    before = Ledger::TableDigest.projections
    Ledger::Replay.call
    expect(Ledger::TableDigest.projections).to eq(before)
  end

  it "rejects a forged adoption, an adoption by an anonymous key, and an unknown code" do
    curator_pair, curator = register_key(display_name: "Curator")
    anon_pair, anonymous = register_key(display_name: "Anon", identity_tier: "ANONYMOUS")
    challenge = Ledger::Appliers::AdoptKey.challenge(curator.key_id, anonymous.key_id)

    expect_rejected("SIGNATURE_INVALID") { append(action_type: "ADOPT_KEY", key_pair: curator_pair, payload: { "key_id" => anonymous.key_id, "adoption_signature" => curator_pair.sign(challenge) }) }
    expect_rejected("NOT_ADOPTABLE") { append(action_type: "ADOPT_KEY", key_pair: curator_pair, payload: { "key_id" => curator.key_id, "adoption_signature" => curator_pair.sign(challenge) }) }
    other_pair, = register_key(display_name: "Other anon", identity_tier: "ANONYMOUS")
    expect_rejected("NOT_AUTHORIZED") { append(action_type: "ADOPT_KEY", key_pair: other_pair, payload: { "key_id" => anonymous.key_id, "adoption_signature" => anon_pair.sign(challenge) }) }

    append(action_type: "ADOPT_KEY", key_pair: curator_pair, payload: { "key_id" => anonymous.key_id, "adoption_signature" => anon_pair.sign(challenge) })
    expect(anonymous.reload.adopted_by_key_id).to eq(curator.key_id)
    # A different payload, so the idempotent resubmission rule does not return the first entry.
    expect_rejected("ALREADY_ADOPTED") { append(action_type: "ADOPT_KEY", key_pair: curator_pair, payload: { "key_id" => anonymous.key_id, "adoption_signature" => anon_pair.sign(challenge), "note" => "again" }) }

    get "/adopt/adopt_nope"
    expect(response).to have_http_status(:not_found).or redirect_to("/session/new")
  end
end
