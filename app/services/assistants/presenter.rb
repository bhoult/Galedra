# frozen_string_literal: true

module Assistants
  module Presenter
    module_function

    def call(token)
      {
        id: token.id, name: token.software["agent_name"], provider: token.software["model_provider"], model: token.software["model_id"],
        agent_key_id: token.agent.key_id, principal_key_id: token.principal.key_id, principal_tier: token.principal.identity_tier,
        delegation_id: token.delegation_id, valid_until: token.delegation.valid_until.utc.iso8601, hourly_cap: token.hourly_cap,
        writes_this_hour: token.writes_this_hour, revoked: !token.usable?
      }
    end
  end
end
