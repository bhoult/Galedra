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

# Evidence-graph builders. Each appends one valid contribution through the real
# write path and returns the projection row it created.
module GraphHelpers
  def row_for(result, kind, model)
    model.find(Ledger::Ids.derive(result.contribution.id, kind))
  end

  def create_source(pair, title: "Source", content: "The quick brown fox jumps over the lazy dog.", type: "PRIMARY_TEXT", delegation: nil, **extra)
    payload = { "source_type" => type, "title" => title, "content" => content, "content_hash" => Crypto::Hashing.bytes(content) }.merge(extra.stringify_keys)
    row_for(append(action_type: "CREATE_SOURCE", key_pair: pair, payload: payload, delegation_id: delegation&.id), "source", Source)
  end

  def create_location(pair, source, start: 0, finish: nil, delegation: nil, **extra)
    finish ||= source.content_length
    excerpt = source.slice(start, finish)
    payload = { "source_id" => source.id, "locator_type" => "CHAR_RANGE", "locator" => { "start" => start, "end" => finish },
                "excerpt" => excerpt, "excerpt_hash" => Crypto::Hashing.bytes(excerpt) }.merge(extra.stringify_keys)
    row_for(append(action_type: "CREATE_SOURCE_LOCATION", key_pair: pair, payload: payload, delegation_id: delegation&.id), "location", SourceLocation)
  end

  def claim_payload(text, type: "TEXTUAL", **extra)
    { "canonical_text" => text, "claim_type" => type, "affirms_not_private_individual" => true }.merge(extra.stringify_keys)
  end

  def create_claim(pair, text, type: "TEXTUAL", delegation: nil, **extra)
    row_for(append(action_type: "CREATE_CLAIM", key_pair: pair, payload: claim_payload(text, type: type, **extra), delegation_id: delegation&.id), "claim", Claim)
  end

  def create_evidence(pair, location, statement: "The passage states it.", observation: "DIRECT_TEXT", delegation: nil, **extra)
    payload = { "source_location_id" => location.id, "observation_type" => observation, "statement" => statement }.merge(extra.stringify_keys)
    row_for(append(action_type: "CREATE_EVIDENCE", key_pair: pair, payload: payload, delegation_id: delegation&.id), "evidence", EvidenceItem)
  end

  def link_evidence(pair, evidence, claim, direction: "SUPPORT", strength: "DIRECT", steps: 0, delegation: nil, **extra)
    payload = { "evidence_item_id" => evidence.id, "claim_id" => claim.id, "direction" => direction,
                "relevance_strength" => strength, "interpretive_steps" => steps }.merge(extra.stringify_keys)
    row_for(append(action_type: "LINK_EVIDENCE", key_pair: pair, payload: payload, delegation_id: delegation&.id), "link", EvidenceClaimLink)
  end

  def create_edge(pair, from, to, type: "NARROWS", delegation: nil)
    payload = { "from_claim_id" => from.id, "to_claim_id" => to.id, "relationship_type" => type }
    row_for(append(action_type: "CREATE_CLAIM_EDGE", key_pair: pair, payload: payload, delegation_id: delegation&.id), "edge", ClaimEdge)
  end

  def create_group(pair, type: "SAME_DATASET", description: nil, delegation: nil)
    payload = { "group_type" => type, "description" => description }
    row_for(append(action_type: "CREATE_INDEPENDENCE_GROUP", key_pair: pair, payload: payload, delegation_id: delegation&.id), "group", IndependenceGroup)
  end

  def assign_group(pair, evidence, group, delegation: nil)
    payload = { "evidence_item_id" => evidence.id, "independence_group_id" => group.id }
    row_for(append(action_type: "ASSIGN_INDEPENDENCE_GROUP", key_pair: pair, payload: payload, delegation_id: delegation&.id), "assignment", IndependenceGroupAssignment)
  end

  def accept(pair, contribution, delegation: nil)
    append(action_type: "ACCEPT", key_pair: pair, payload: { "contribution_id" => contribution.id }, delegation_id: delegation&.id).contribution
  end

  def invalidate(pair, contribution, reason: "withdrawn", delegation: nil)
    append(action_type: "INVALIDATE", key_pair: pair, payload: { "contribution_id" => contribution.id, "reason" => reason }, delegation_id: delegation&.id).contribution
  end

  # Registers a key and designates it a moderator for the rest of the example.
  def register_moderator(**payload)
    pair, contributor = register_key(display_name: "Moderator", **payload)
    ENV[Governance::Moderators::ENV_KEY] = [ ENV[Governance::Moderators::ENV_KEY], pair.key_id ].compact.reject(&:empty?).join(",")
    [ pair, contributor ]
  end

  def quarantine(pair, target, reason: "PRIVATE_INDIVIDUAL", note: nil)
    type = target.is_a?(Claim) ? "CLAIM" : "SOURCE"
    result = append(action_type: "QUARANTINE", key_pair: pair, payload: { "target_type" => type, "target_id" => target.id, "reason" => reason, "note" => note })
    Quarantine.find(Ledger::Ids.derive(result.contribution.id, "quarantine"))
  end

  def takedown(pair, contribution, legal_basis: "Court order 2026-17", removed: nil)
    manifest = Ledger::Redaction.manifest_for(contribution, removed: removed)
    append(action_type: "TAKEDOWN", key_pair: pair,
           payload: { "contribution_id" => contribution.id, "legal_basis" => legal_basis, "requested_at" => Date.today.iso8601,
                      "redaction_manifest" => manifest }).contribution
  end

  # A human principal with a delegated agent: [principal_pair, agent_pair, agent, delegation].
  def principal_with_agent(**delegation_options)
    principal_pair, = register_key
    agent_pair, agent = register_key(kind: Contributor::AGENT)
    delegation = delegate(principal_pair, agent, **delegation_options)
    [ principal_pair, agent_pair, agent, delegation ]
  end
end

RSpec.configure { |c| c.include GraphHelpers }

module ScoringHelpers
  def default_config = Scoring::Registry.load_config(Rails.root.join("config/scoring/ledger-default-0.1.0.json"))
  def strict_config = Scoring::Registry.load_config(Rails.root.join("config/scoring/ledger-strict-0.1.0.json"))

  def release_models
    Scoring::Registry.config_files.map do |path|
      config = Scoring::Registry.load_config(path)
      next Scoring::Registry.find(Scoring::Registry.model_name(config)) if ScoringModel.exists?(name: config["name"], semantic_version: config["semantic_version"])

      result = append(action_type: "RELEASE_SCORING_MODEL", key_pair: Crypto::SystemKey.key_pair, custody: Crypto::Custody::SYSTEM,
                      payload: Scoring::Registry.release_payload(config))
      ScoringModel.find(Ledger::Ids.derive(result.contribution.id, "scoring_model"))
    end
  end

  def golden
    @golden ||= JSON.parse(File.read(Rails.root.join("spec/fixtures/scoring_golden.json")))
  end

  def golden_fields(result)
    {
      "assessment_state" => result.assessment_state, "probability" => result.probability, "stability" => result.stability,
      "review_coverage" => result.review_coverage, "support_groups" => result.support_groups,
      "contradict_groups" => result.contradict_groups, "independence_unreviewed" => result.independence_unreviewed,
      "not_applicable_reason" => result.not_applicable_reason, "contested" => result.contested, "provisional" => result.provisional
    }
  end
end

RSpec.configure { |c| c.include ScoringHelpers }
