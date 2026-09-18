# frozen_string_literal: true

module Assistants
  # Revoking a token appends REVOKE_DELEGATION signed by the principal, so the
  # revocation is visible in the log like the grant was.
  module Revoke
    module_function

    def call(token, reason: "assistant disconnected")
      return token if token.revoked?

      unless token.delegation.revoked?
        envelope = Contributions::Envelope.build(action_type: "REVOKE_DELEGATION", payload: { "delegation_id" => token.delegation_id, "reason" => reason },
                                                key_pair: Crypto::Custody.signer_for_contributor(token.principal))
        Ledger::Append.call(envelope, custody: Crypto::Custody::SERVER)
      end
      token.update!(revoked_at: Time.current)
      OauthToken.where(assistant_token: token, revoked_at: nil).update_all(revoked_at: Time.current)
      token
    end
  end
end
