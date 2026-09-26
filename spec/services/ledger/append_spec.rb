require "rails_helper"

RSpec.describe Ledger::Append do
  describe "genesis (07 Phase 1 #8)" do
    it "has seq 0 as the pinned system key's self-signed REGISTER_KEY with SYSTEM custody" do
      genesis = Contribution.find_by!(seq: 0)
      expect(genesis.action_type).to eq("REGISTER_KEY")
      expect(genesis.custody).to eq(Crypto::Custody::SYSTEM)
      expect(genesis.contributor_id).to be_nil
      expect(genesis.prev_hash).to eq("0" * 64)
      expect(genesis.signer_key_id).to eq(Crypto::SystemKey.key_id)
      expect(genesis.payload["public_key"]).to eq(Crypto::SystemKey.public_key)
      expect(Contributor.find_by!(key_id: genesis.signer_key_id)).to be_system
    end

    it "refuses anything but the pinned system key into an empty log, then accepts it" do
      as_owner { Contribution.delete_all }
      Contributor.delete_all
      expect_rejected("GENESIS_REQUIRED") { register_key }
      expect(Contribution.count).to eq(0)

      genesis = Ledger::Genesis.ensure!
      expect(genesis.seq).to eq(0)
      expect(Ledger::Genesis.ensure!).to eq(genesis)
    end

    it "refuses to append when the configured key is not the one registered at seq 0" do
      other = key_pair
      with_env(Crypto::SystemKey::PRIVATE_ENV => other.private_key, Crypto::SystemKey::PUBLIC_ENV => other.public_key) do
        expect { register_key }.to raise_error(Ledger::GenesisMismatch)
      end
    end

    it "never registers a second SYSTEM key" do
      expect_rejected("NOT_AUTHORIZED") { register_key(kind: Contributor::SYSTEM) }
    end
  end

  describe "REGISTER_KEY" do
    it "creates the contributor with a deterministic id and a valid chain entry" do
      pair, contributor = register_key(display_name: "Alice", identity_tier: "ESTABLISHED")
      c = Contribution.find_by!(signer_key_id: pair.key_id)

      expect(c.contributor_id).to be_nil
      expect(c.action_class).to eq(Contribution::CONTROL)
      expect(c.current_status).to eq(Contribution::ACCEPTED)
      expect(c.custody).to eq(Crypto::Custody::SELF)
      expect(contributor.id).to eq(Ledger::Ids.derive(c.id, "contributor"))
      expect(contributor.display_name).to eq("Alice")
      expect(contributor.identity_tier).to eq("ESTABLISHED")
      expect(contributor.created_seq).to eq(c.seq)

      previous = Contribution.find_by!(seq: c.seq - 1)
      expect(c.prev_hash).to eq(previous.entry_hash)
      expect(c.entry_hash).to eq(Ledger::Entry.hash(seq: c.seq, prev_hash: c.prev_hash, envelope_hash: c.envelope_hash, received_at: c.received_at))
      expect(c.envelope_hash).to eq(Crypto::Hashing.json(c.envelope))
      expect(Ledger::Entry.server_signature_ok?(c.entry_hash, c.server_signature)).to be(true)
      expect(Ledger::Verify.entry(c)).to eq(client_signature_ok: true, server_signature_ok: true, chain_ok: true)
    end

    it "rejects a signer_key_id that is not the hash of the registered public key" do
      pair = key_pair
      envelope = build_envelope(action_type: "REGISTER_KEY", key_pair: pair, payload: { "public_key" => key_pair.public_key, "kind" => "HUMAN" })
      expect_rejected("KEY_ID_MISMATCH") { Ledger::Append.call(envelope) }
    end

    it "rejects registering the same key twice" do
      pair, = register_key
      expect_rejected("KEY_ALREADY_REGISTERED") { append(action_type: "REGISTER_KEY", key_pair: pair, payload: { "public_key" => pair.public_key, "kind" => "HUMAN", "display_name" => "again" }) }
    end
  end

  describe "signer resolution" do
    it "rejects when signer_key_id and the signing key disagree" do
      alice, = register_key
      mallory, = register_key
      envelope = build_envelope(action_type: "CREATE_CLAIM", key_pair: mallory, payload: claim_payload("x"))
      envelope["signer_key_id"] = alice.key_id
      expect_rejected("SIGNATURE_INVALID") { Ledger::Append.call(envelope) }
    end

    it "rejects unknown keys and tampered envelopes" do
      expect_rejected("KEY_UNKNOWN") { append(action_type: "CREATE_CLAIM", key_pair: key_pair, payload: claim_payload("x")) }

      pair, = register_key
      envelope = build_envelope(action_type: "CREATE_CLAIM", key_pair: pair, payload: claim_payload("x"))
      tampered = envelope.merge("payload" => claim_payload("y"), "payload_hash" => Crypto::Hashing.json(claim_payload("y")))
      expect_rejected("SIGNATURE_INVALID") { Ledger::Append.call(tampered) }
      expect_rejected("PAYLOAD_HASH_MISMATCH") { Ledger::Append.call(envelope.merge("payload" => claim_payload("y"))) }
    end

    it "rejects floats, unknown action types, unknown fields, and not-yet-supported actions" do
      pair, = register_key
      with_float = build_envelope(action_type: "CREATE_CLAIM", key_pair: pair, payload: claim_payload("x")).merge("payload" => { "weight" => 0.5 })
      expect_rejected("FLOAT_PRESENT") { Ledger::Append.call(with_float) }
      expect_rejected("UNKNOWN_ACTION_TYPE") { append(action_type: "DELETE_EVERYTHING", key_pair: pair, payload: {}) }
      expect_rejected("NOT_AUTHORIZED") { append(action_type: "AMEND_CONSTITUTION", key_pair: pair, payload: {}) }
      expect_rejected("SCHEMA_INVALID") { append(action_type: "TASK_RESULT", key_pair: pair, payload: {}) }
      envelope = build_envelope(action_type: "CREATE_CLAIM", key_pair: pair, payload: claim_payload("x")).merge("extra" => 1)
      expect_rejected("SCHEMA_INVALID") { Ledger::Append.call(envelope) }
    end
  end

  describe "custody" do
    it "reserves SYSTEM custody for the system key and refuses the system key elsewhere" do
      pair, = register_key
      expect_rejected("NOT_AUTHORIZED") { append(action_type: "CREATE_CLAIM", key_pair: pair, payload: claim_payload("x"), custody: Crypto::Custody::SYSTEM) }
      expect_rejected("NOT_AUTHORIZED") { append(action_type: "CREATE_CLAIM", key_pair: Crypto::SystemKey.key_pair, payload: claim_payload("x"), custody: Crypto::Custody::SELF) }
    end
  end

  describe "epistemic contributions" do
    it "are logged and, for a human's own work, accepted by the system in the same transaction" do
      pair, contributor = register_key
      result = append(action_type: "CREATE_CLAIM", key_pair: pair, payload: claim_payload("The sky is blue."))
      c = result.contribution
      expect(result.created).to be(true)
      expect(c.action_class).to eq(Contribution::EPISTEMIC)
      expect(c.contributor_id).to eq(contributor.id)
      expect(c.reload.current_status).to eq(Contribution::ACCEPTED)
      expect(result.acceptance.action_type).to eq("ACCEPT")
      expect(result.acceptance.custody).to eq(Crypto::Custody::SYSTEM)
      expect(result.acceptance.seq).to eq(c.seq + 1)
    end

    it "stay PENDING as proposals when made by an agent" do
      _, agent_pair, _, delegation = principal_with_agent
      result = append(action_type: "CREATE_CLAIM", key_pair: agent_pair, delegation_id: delegation.id, payload: claim_payload("Proposed."))
      expect(result.contribution.current_status).to eq(Contribution::PENDING)
      expect(result.acceptance).to be_nil
    end
  end

  describe "idempotency (07 Phase 1 #7)" do
    it "returns the original contribution for a duplicate submission" do
      pair, = register_key
      envelope = build_envelope(action_type: "CREATE_CLAIM", key_pair: pair, payload: claim_payload("once"))
      first = Ledger::Append.call(envelope)
      again = Ledger::Append.call(envelope)
      expect(again.created).to be(false)
      expect(again.contribution).to eq(first.contribution)
      expect(Contribution.where(idempotency_key: first.contribution.idempotency_key).count).to eq(1)
    end
  end
end
