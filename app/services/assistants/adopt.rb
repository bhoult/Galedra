# frozen_string_literal: true

module Assistants
  # Puts an anonymous assistant's work under a signed-in person's key by
  # appending ADOPT_KEY, signed by the person's server-custodied key with a
  # counter-signature from the anonymous principal's key, which the server
  # also holds. The token then belongs to the account too.
  module Adopt
    class NotAdoptable < StandardError; end

    module_function

    def call(token, user)
      raise NotAdoptable, "this work is already under an account" unless token.anonymous?
      raise NotAdoptable, "this assistant's key is revoked" if token.principal.revoked?

      adopter = user.custodied_key&.contributor || Crypto::Custody.create_server_custodied(user: user, display_name: user.email_address.split("@").first)
      anonymous = token.principal
      challenge = Ledger::Appliers::AdoptKey.challenge(adopter.key_id, anonymous.key_id)
      counter = Crypto::Custody.signer_for_contributor(anonymous).sign(challenge)
      envelope = Contributions::Envelope.build(action_type: "ADOPT_KEY", payload: { "key_id" => anonymous.key_id, "adoption_signature" => counter },
                                              key_pair: Crypto::Custody.signer_for(user))
      result = Ledger::Append.call(envelope, custody: Crypto::Custody::SERVER)
      token.update!(user: user)
      result.contribution
    end

    def adopt_url(token, base_url)
      return nil unless token.anonymous? && token.adoption_code.present?

      "#{base_url}/adopt/#{token.adoption_code}"
    end
  end
end
