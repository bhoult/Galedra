# frozen_string_literal: true

module Ui
  # Every UI write is a signed contribution through the one write path,
  # signed with the user's server-custodied key (spec 05 §2, 06 §1).
  module Write
    module_function

    def call(user, action_type, payload)
      signer = Crypto::Custody.signer_for(user)
      envelope = Contributions::Envelope.build(action_type: action_type, payload: payload, key_pair: signer)
      Ledger::Append.call(envelope, custody: Crypto::Custody::SERVER)
    end

    def contributor_for(user)
      user.custodied_key&.contributor
    end
  end
end
