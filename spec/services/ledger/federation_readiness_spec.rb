require "rails_helper"

RSpec.describe "Federation readiness (Stage 23, spec 14 §5, §7, §10, §25)" do
  include LedgerHelpers

  describe "a key's home node" do
    it "records home_url on REGISTER_KEY and reports this node when absent" do
      with_env("LEDGER_NODE_URL" => "https://ledger.example.org/") do
        _, local = register_key
        expect(local.home_url).to be_nil
        expect(local.home_node_url).to eq("https://ledger.example.org")

        _, remote = register_key(home_url: "https://other.example.net")
        expect(remote.home_url).to eq("https://other.example.net")
        expect(Graph::Presenter.contributor(remote)[:home_url]).to eq("https://other.example.net")
      end
    end

    it "rejects a home_url that is not a plain http(s) origin" do
      [ "ftp://x.example", "https://x.example/?q=1", "https://user:pw@x.example", "not a url", "https://" + ("a" * 200) + ".example" ].each do |bad|
        expect_rejected("SCHEMA_INVALID") { register_key(home_url: bad) }
      end
    end
  end

  it "marks every log entry PUBLIC and says so in the API" do
    _, contributor = register_key
    expect(contributor.contributions.first || Contribution.find_by(signer_key_id: contributor.key_id)).to have_attributes(visibility: "PUBLIC")
    expect(Contributions::Presenter.entry(Contribution.find_by(signer_key_id: contributor.key_id))[:visibility]).to eq("PUBLIC")
  end

  describe "signed checkpoints" do
    it "signs a checkpoint when a snapshot is pinned, chained to the previous one, and verifies it" do
      register_key
      first = Snapshots::Create.call(seq: 0, label: "genesis")
      second = Snapshots::Create.call(seq: Contribution.maximum(:seq))

      expect(first.checkpoint).to include("protocol" => Ledger::Node::CHECKPOINT_PROTOCOL, "seq" => 0, "entry_hash" => first.entry_hash,
                                          "previous_checkpoint_seq" => nil, "node_key_id" => Crypto::SystemKey.key_id)
      expect(second.checkpoint["previous_checkpoint_seq"]).to eq(0)
      expect(Snapshots::Checkpoint.verify(first.checkpoint)).to be(true)
      expect(Snapshots::Checkpoint.verify(second.checkpoint)).to be(true)

      tampered = second.checkpoint.merge("seq" => 99)
      expect(Snapshots::Checkpoint.verify(tampered)).to be(false)
      expect(Snapshots::Checkpoint.verify(second.checkpoint, public_key: Crypto::Ed25519::KeyPair.generate.public_key)).to be(false)
    end
  end

  it "publishes the node identity in meta" do
    expect(Ledger::Node.to_h).to include(:url, :key_id, :protocol, :schema_version, :checkpoint_protocol, :data_license, :visibilities, :software)
    expect(Ledger::Node.to_h[:software]).to include(:name, :revision, :repository, :ruby, :rails)
    with_env("LEDGER_NODE_URL" => nil, "LEDGER_ALLOWED_HOSTS" => ".trycloudflare.com, galedra.example") do
      expect(Ledger::Node.url).to eq("https://galedra.example")
    end
    with_env("LEDGER_DATA_LICENSE" => "CC0-1.0") do
      expect(Ledger::Node.data_license).to eq("CC0-1.0")
    end
  end
end
