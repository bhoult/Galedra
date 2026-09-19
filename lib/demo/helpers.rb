# frozen_string_literal: true

module Demo
  # Builds real contributions through the write path, outside RSpec. Mirrors
  # spec/support helpers step for step so the seeds and the specs agree.
  class Helpers
    attr_reader :agents

    def initialize(base_url: ENV.fetch("LEDGER_BASE_URL", "http://localhost:3000"))
      @base_url = base_url
      @agents = {}
    end

    def key_pair = Crypto::Ed25519::KeyPair.generate

    def append(action_type:, payload:, key_pair:, custody: Crypto::Custody::SELF, **options)
      Ledger::Append.call(Contributions::Envelope.build(action_type: action_type, payload: payload, key_pair: key_pair, **options), custody: custody)
    end

    def row_for(result, kind, model) = model.find(Ledger::Ids.derive(result.contribution.id, kind))

    def register_key(pair = key_pair, kind: Contributor::HUMAN, **payload)
      append(action_type: "REGISTER_KEY", key_pair: pair, payload: { "public_key" => pair.public_key, "kind" => kind }.merge(payload.stringify_keys))
      [ pair, Contributor.find_by!(key_id: pair.key_id) ]
    end

    # A browser user with a server-custodied key (spec 08 §3: Curator, Reviewer).
    def register_server_user(email, display_name:, identity_tier: "PSEUDONYMOUS")
      user = User.find_by(email_address: email) || User.create!(email_address: email, password: SecureRandom.hex(12))
      contributor = user.custodied_key&.contributor || Crypto::Custody.create_server_custodied(user: user, display_name: display_name, identity_tier: identity_tier)
      [ Crypto::Custody.signer_for(user), contributor, user ]
    end

    def server_append(user, action_type, payload, **options)
      Ledger::Append.call(Contributions::Envelope.build(action_type: action_type, payload: payload, key_pair: Crypto::Custody.signer_for(user), **options), custody: Crypto::Custody::SERVER)
    end

    def delegate(principal_pair, agent, domains:, valid_until: 30.days.from_now, custody: Crypto::Custody::SELF, user: nil)
      payload = { "delegate_key_id" => agent.key_id, "permissions" => { "allowed_task_types" => Tasks::Types::ALL, "domains" => domains },
                  "valid_from" => 1.minute.ago.utc.iso8601, "valid_until" => valid_until.utc.iso8601 }
      result = user ? server_append(user, "DELEGATE", payload) : append(action_type: "DELEGATE", key_pair: principal_pair, payload: payload, custody: custody)
      AgentDelegation.find(Ledger::Ids.derive(result.contribution.id, "delegation"))
    end

    def create_source(user, title:, content:, type: "PRIMARY_TEXT", **extra)
      payload = { "source_type" => type, "title" => title, "content" => content, "content_hash" => Crypto::Hashing.bytes(content) }.merge(extra.stringify_keys)
      row_for(server_append(user, "CREATE_SOURCE", payload), "source", Source)
    end

    def create_location(user, source)
      payload = { "source_id" => source.id, "locator_type" => "CHAR_RANGE", "locator" => { "start" => 0, "end" => source.content_length },
                  "excerpt" => source.content, "excerpt_hash" => Crypto::Hashing.bytes(source.content) }
      row_for(server_append(user, "CREATE_SOURCE_LOCATION", payload), "location", SourceLocation)
    end

    def create_claim(user, text, type:)
      row_for(server_append(user, "CREATE_CLAIM", { "canonical_text" => text, "claim_type" => type, "affirms_not_private_individual" => true }), "claim", Claim)
    end

    def create_evidence(user, location, statement:, observation: "DIRECT_TEXT")
      row_for(server_append(user, "CREATE_EVIDENCE", { "source_location_id" => location.id, "observation_type" => observation, "statement" => statement }), "evidence", EvidenceItem)
    end

    def link(user, evidence, claim, direction: "SUPPORT", strength: "DIRECT", steps: 0, note: nil)
      payload = { "evidence_item_id" => evidence.id, "claim_id" => claim.id, "direction" => direction, "relevance_strength" => strength, "interpretive_steps" => steps, "note" => note }.compact
      row_for(server_append(user, "LINK_EVIDENCE", payload), "link", EvidenceClaimLink)
    end

    def create_group(user, type:, description:)
      row_for(server_append(user, "CREATE_INDEPENDENCE_GROUP", { "group_type" => type, "description" => description }), "group", IndependenceGroup)
    end

    def assign(user, evidence, group)
      row_for(server_append(user, "ASSIGN_INDEPENDENCE_GROUP", { "evidence_item_id" => evidence.id, "independence_group_id" => group.id }), "assignment", IndependenceGroupAssignment)
    end

    def accept(user, contribution)
      server_append(user, "ACCEPT", { "contribution_id" => contribution.id }).contribution
    end

    def audit(user, target, result: "CONFIRMED", type: "SOURCE_CHECK", note: nil)
      target = target.contribution if target.respond_to?(:contribution) && !target.is_a?(Contribution)
      payload = { "target_contribution_id" => target.id, "audit_type" => type, "result" => result, "note" => note }.compact
      Audit.find(Ledger::Ids.derive(server_append(user, "AUDIT", payload).contribution.id, "audit"))
    end

    def create_task(type, target, location: nil, domain: "general")
      Tasks::Create.call(task_type: type, target: target, location: location, domain: domain)
    end

    def snapshot(label)
      Snapshots::Create.call(seq: Contribution.maximum(:seq), label: label)
    end

    # The fixture-driven example agent, in-process through the Rack stack.
    def agent(name, key:, delegation:, fixtures_agent: "good")
      @agents[name] ||= begin
        load Rails.root.join("examples/agent/agent.rb") unless defined?(Galedra::Client)
        mock = Rack::MockRequest.new(Rails.application)
        env = { "HTTP_HOST" => "localhost", "REMOTE_ADDR" => "127.0.0.1" }
        transport = lambda do |method, path, body|
          response = method == :get ? mock.get(path, env) : mock.post(path, env.merge(input: body, "CONTENT_TYPE" => "application/json"))
          [ response.status, response.body ]
        end
        client = Galedra::Client.new(base_url: @base_url, key_file: { "private_key" => key.private_key, "public_key" => key.public_key, "key_id" => key.key_id },
                                     delegation_id: delegation.id, transport: transport)
        verifier = Galedra::StubVerifier.new(JSON.parse(File.read(Rails.root.join("examples/agent/fixtures.json"))), agent: fixtures_agent)
        [ client, verifier ]
      end
    end

    # Leases the given task with the named agent, answers from fixtures, submits. Returns the result contribution.
    #
    # A claim can have more than one open task of a kind, since verification now
    # opens with the claim, and the demo wants the one it just made, whose
    # packet lists the links as they stand. Leasing never hands back what this
    # agent already holds, so asking again walks past the others.
    def run_task(name, task)
      client, verifier = @agents.fetch(name)
      lease = nil
      5.times do
        lease = client.lease_next(types: [ task.task_type ], domains: [ task.domain ])
        break if lease.nil? || lease["assignment"]["task_id"] == task.id
      end
      raise "agent #{name} could not lease #{task.task_type}" if lease.nil? || lease["assignment"]["task_id"] != task.id

      packet = client.verify_packet!(lease["packet"])
      answer = verifier.run(packet)
      body = client.submit(packet, outcome: answer["outcome"], ops: answer["ops"])
      Contribution.find(body["contribution"]["id"])
    end
  end
end
