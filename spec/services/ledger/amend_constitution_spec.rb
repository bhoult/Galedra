require "rails_helper"

# Article XXV: an amendment takes effect only once recorded in the ledger as a
# signed AMEND_CONSTITUTION carrying the version and hash of the text served.
# Until 2026-09-23 the action type was reserved and refused, so no node had
# ever signed which constitution it followed.
RSpec.describe "AMEND_CONSTITUTION", type: :request do
  let(:constitution) { Governance::Constitution.new }

  def amend(payload, key_pair: Crypto::SystemKey.key_pair)
    append(action_type: "AMEND_CONSTITUTION", key_pair: key_pair, custody: Crypto::Custody::SYSTEM, payload: payload)
  end

  it "records the text served, once, and /meta then says it matches" do
    contribution = Ledger::AdoptConstitution.call
    expect(contribution.payload).to include("version" => constitution.version, "constitution_hash" => constitution.digest)
    expect(contribution.current_status).to eq(Contribution::ACCEPTED)
    expect(Ledger::AdoptConstitution.call).to be_nil

    get "/api/v1/meta"
    expect(response.parsed_body["constitution_recorded"]).to include("seq" => contribution.seq, "matches" => true)
  end

  it "reports nothing recorded rather than a match on a log that never recorded one" do
    get "/api/v1/meta"
    expect(response.parsed_body["constitution_recorded"]).to be_nil
  end

  it "refuses a hash or version other than the text served" do
    expect_rejected("CONSTITUTION_HASH_MISMATCH") { amend({ "version" => constitution.version, "constitution_hash" => "sha256:#{'0' * 64}" }) }
    expect_rejected("VERSION_MISMATCH") { amend({ "version" => "9.9.9", "constitution_hash" => constitution.digest }) }
  end

  it "refuses any signer but the system key, and logs nothing" do
    pair, = register_key
    count = Contribution.count
    expect_rejected("NOT_AUTHORIZED") do
      amend({ "version" => constitution.version, "constitution_hash" => constitution.digest }, key_pair: pair)
    end
    expect(Contribution.count).to eq(count)
  end

  it "replays without asking the file again" do
    Ledger::AdoptConstitution.call
    expect(Ledger::Replay.call.status).to eq("REPLAYED")
  end
end
