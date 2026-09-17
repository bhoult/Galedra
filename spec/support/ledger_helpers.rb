# Builds and appends real signed contributions through Ledger::Append.
module LedgerHelpers
  def key_pair = Crypto::Ed25519::KeyPair.generate

  def build_envelope(action_type:, payload:, key_pair:, **options)
    Contributions::Envelope.build(action_type: action_type, payload: payload, key_pair: key_pair, **options)
  end

  def append(action_type:, payload:, key_pair:, custody: Crypto::Custody::SELF, **options)
    Ledger::Append.call(build_envelope(action_type: action_type, payload: payload, key_pair: key_pair, **options), custody: custody)
  end

  # Registers a key and returns [key_pair, contributor].
  def register_key(pair = key_pair, kind: Contributor::HUMAN, **payload)
    append(action_type: "REGISTER_KEY", key_pair: pair,
           payload: { "public_key" => pair.public_key, "kind" => kind }.merge(payload.stringify_keys))
    [ pair, Contributor.find_by!(key_id: pair.key_id) ]
  end

  def delegate(principal_pair, agent_contributor, permissions: nil, valid_from: 1.minute.ago, valid_until: 1.day.from_now, **extra)
    permissions ||= { "allowed_task_types" => [ "EVIDENCE_VERIFICATION" ], "domains" => [ "general" ] }
    result = append(action_type: "DELEGATE", key_pair: principal_pair,
                    payload: { "delegate_key_id" => agent_contributor.key_id, "permissions" => permissions,
                               "valid_from" => valid_from.utc.iso8601, "valid_until" => valid_until.utc.iso8601 }.merge(extra))
    AgentDelegation.find(Ledger::Ids.derive(result.contribution.id, "delegation"))
  end

  def as_owner(&) = Ledger::DatabaseRole.as_owner(&)

  def expect_rejected(code)
    expect { yield }.to raise_error(Ledger::Rejected) { |e| expect(e.errors.map { |x| x[:code] }).to include(code) }
  end
end
