FactoryBot.define do
  factory :contributor do
    transient do
      key_pair { Crypto::Ed25519::KeyPair.generate }
    end

    kind { Contributor::HUMAN }
    identity_tier { "PSEUDONYMOUS" }
    public_key { key_pair.public_key }
    key_id { key_pair.key_id }

    trait :agent do
      kind { Contributor::AGENT }
    end

    trait :server_custodied do
      user
      encrypted_private_key { key_pair.private_key }
    end
  end
end
