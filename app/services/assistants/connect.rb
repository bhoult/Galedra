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

    # `origin` says where the token came from and decides what it may do, so it
    # is named at every mint rather than inferred later. The default is the
    # honest reading of this method's own arguments: with a person, USER;
    # without, ADDRESS, until a caller says otherwise.
    def call(user: nil, name:, provider:, model: nil, hourly_cap: nil, origin: nil, kin_key: nil)
      hourly_cap ||= user ? NAMED_HOURLY_CAP : DEFAULT_HOURLY_CAP
      name = name.to_s.strip
      raise ArgumentError, "assistant name is required" if name.empty?
      raise ArgumentError, "unknown provider" unless AssistantToken::PROVIDERS.include?(provider.to_s)

      principal = principal_for(user)
      software = { "agent_name" => name, "version" => "connected", "model_provider" => provider.to_s, "model_id" => model.presence || "unknown", "prompt_version" => "galedra-skill-v1" }
      agent = Crypto::Custody.create_server_custodied(
        kind: Contributor::AGENT, identity_tier: principal.identity_tier,
        display_name: "#{name} for #{principal.public_label}", metadata: { "software" => software }
      )
      delegation = delegate(principal, agent, hourly_cap)
      plaintext = "gal_#{SecureRandom.urlsafe_base64(32)}"
      record = AssistantToken.create!(
        id: SecureRandom.uuid_v7, token_digest: AssistantToken.digest(plaintext), agent: agent, principal: principal,
        delegation: delegation, user: user, software: software, hourly_cap: hourly_cap,
        origin: origin || (user ? "USER" : "CONNECTOR"), kin_key: kin_key
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

      # No kin key: an address-keyed token is not an identity, so there is
      # nothing to group it with and nothing it may work.
      record, = call(name: name, provider: "other", model: "unknown", origin: "ADDRESS")
      record.update!(source_key: key)
      record
    rescue ActiveRecord::RecordNotUnique
      AssistantToken.find_by!(source_key: key)
    end

    def principal_for(user)
      return user.custodied_key&.contributor || Crypto::Custody.create_server_custodied(user: user) if user

      Crypto::Custody.create_server_custodied(display_name: "Anonymous", identity_tier: "ANONYMOUS")
    end

    # A person behind an assistant earns the named caps whenever the person
    # arrives: at the mint, or later by adoption. Adoption used to leave a
    # self-minted token at 500 writes and 500 leases an hour, and a worker the
    # owner had adopted stopped at both on 2026-09-28 (feature requests
    # 01a0e968, 01a0e9d4-9115, 01a0e9d4-9ade). The owner's word: "this is
    # normal usage for an agent." The lease limit is part of the signed
    # delegation, so it rises by a new DELEGATE from the same principal with the
    # same permissions: whose work it is does not change, only how much of it.
    # Idempotent; bin/rails assistants:named_caps applies it to tokens adopted
    # before this existed.
    def raise_to_named_caps!(token)
      old = token.delegation
      delegation = old.max_tasks_per_hour && old.max_tasks_per_hour < NAMED_HOURLY_CAP ? delegate(old.principal, token.agent, NAMED_HOURLY_CAP, permissions: old.permissions) : old
      token.update!(hourly_cap: [ token.hourly_cap, NAMED_HOURLY_CAP ].max, delegation: delegation)
      token
    end

    DEFAULT_PERMISSIONS = { "allowed_task_types" => Tasks::Types::ALL, "direct_work" => true, "allowed_actions" => [ "ACCEPT" ] }.freeze

    def delegate(principal, agent, hourly_cap, permissions: DEFAULT_PERMISSIONS.merge("domains" => Audits::Policy.domains))
      now = Time.now.utc
      payload = { "delegate_key_id" => agent.key_id, "permissions" => permissions,
                  "max_tasks_per_hour" => hourly_cap, "valid_from" => (now - 1.minute).iso8601, "valid_until" => (now + VALIDITY).iso8601 }
      envelope = Contributions::Envelope.build(action_type: "DELEGATE", payload: payload, key_pair: Crypto::Custody.signer_for_contributor(principal))
      result = Ledger::Append.call(envelope, custody: Crypto::Custody::SERVER)
      AgentDelegation.find(Ledger::Ids.derive(result.contribution.id, "delegation"))
    end
  end
end
