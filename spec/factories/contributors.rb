FactoryBot.define do
  # Unit-test convenience only: bypasses the log. Integration specs register
  # keys through Ledger::Append (see LedgerHelpers#register_key).
  factory :contributor do
    transient do
      key_pair { Crypto::Ed25519::KeyPair.generate }
    end

    kind { Contributor::HUMAN }
    identity_tier { "PSEUDONYMOUS" }
    public_key { key_pair.public_key }
    key_id { key_pair.key_id }
    created_seq { 0 }

    to_create { |instance| Ledger.applying { instance.save! } }

    trait :agent do
      kind { Contributor::AGENT }
    end
  end
end
