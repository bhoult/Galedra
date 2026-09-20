# frozen_string_literal: true

module Assistants
  # Connects an assistant (Stage 12): registers a server-custodied AGENT key
  # named for the assistant, appends a DELEGATE from the principal, and mints
  # a bearer token. The principal is the signed-in user's key, or a freshly
  # registered anonymous key when there is no account. Returns
  # [token_record, plaintext_token]; the plaintext is never stored.
  module Connect
    # Owner decision: delegations to connected assistants do not expire on their own.
    VALIDITY = 100.years
    DEFAULT_HOURLY_CAP = 500
    # Stage 21: an assistant with a person behind it may record a large source over a day.
    # A first pass over a two-hour transcript measured about 1,600 writes, so
    # this carries two complete investigations in one window with headroom.
    NAMED_HOURLY_CAP = 5_000

    module_function

    def call(user: nil, name:, provider:, model: nil, hourly_cap: nil)
      hourly_cap ||= user ? NAMED_HOURLY_CAP : DEFAULT_HOURLY_CAP
      name = name.to_s.strip
      raise ArgumentError, "assistant name is required" if name.empty?
      raise ArgumentError, "unknown provider" unless AssistantToken::PROVIDERS.include?(provider.to_s)

      principal = principal_for(user)
      software = { "agent_name" => name, "version" => "connected", "model_provider" => provider.to_s, "model_id" => model.presence || "unknown", "prompt_version" => "galedra-skill-v1" }
      agent = Crypto::Custody.create_server_custodied(
        kind: Contributor::AGENT, identity_tier: principal.identity_tier,
        display_name: "#{name} for #{principal.display_name || 'an anonymous contributor'}", metadata: { "software" => software }
      )
      delegation = delegate(principal, agent, hourly_cap)
      plaintext = "gal_#{SecureRandom.urlsafe_base64(32)}"
      record = AssistantToken.create!(
        id: SecureRandom.uuid_v7, token_digest: AssistantToken.digest(plaintext), agent: agent, principal: principal,
        delegation: delegation, user: user, software: software, hourly_cap: hourly_cap
      )
      [ record, plaintext ]
    end

    # A tokenless anonymous assistant for a calling source (an address), one per
    # source per day, minted on first use. Nothing is handed out: the record is
    # found again by its source key, and the same caps and sampling apply.
    def for_source(address, name: "Anonymous assistant")
      key = Digest::SHA256.hexdigest("#{address}|#{Date.current}")
      existing = AssistantToken.find_by(source_key: key)
      return existing if existing&.usable?

      record, = call(name: name, provider: "other", model: "unknown")
      record.update!(source_key: key)
      record
    rescue ActiveRecord::RecordNotUnique
      AssistantToken.find_by!(source_key: key)
    end

    def principal_for(user)
      return user.custodied_key&.contributor || Crypto::Custody.create_server_custodied(user: user, display_name: user.email_address.split("@").first) if user

      Crypto::Custody.create_server_custodied(display_name: "Anonymous", identity_tier: "ANONYMOUS")
    end

    def delegate(principal, agent, hourly_cap)
      now = Time.now.utc
      payload = { "delegate_key_id" => agent.key_id,
                  "permissions" => { "allowed_task_types" => Tasks::Types::ALL, "domains" => Audits::Policy.domains, "direct_work" => true, "allowed_actions" => [ "ACCEPT" ] },
                  "max_tasks_per_hour" => hourly_cap, "valid_from" => (now - 1.minute).iso8601, "valid_until" => (now + VALIDITY).iso8601 }
      envelope = Contributions::Envelope.build(action_type: "DELEGATE", payload: payload, key_pair: Crypto::Custody.signer_for_contributor(principal))
      result = Ledger::Append.call(envelope, custody: Crypto::Custody::SERVER)
      AgentDelegation.find(Ledger::Ids.derive(result.contribution.id, "delegation"))
    end
  end
end
