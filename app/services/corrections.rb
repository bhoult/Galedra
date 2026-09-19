# frozen_string_literal: true

# Stage 19: corrections from a connector and from the claim page. Every
# correction is a new contribution (Invariant 3): a revised claim, a merge, a
# revised link, a blind task for someone else, or the acceptance of a proposal.
# Own work is accepted at once; someone else's is a proposal until an entitled
# different principal accepts it. Invalidation stays with audits.
module Corrections
  PROPOSAL_ACTIONS = %w[SUPERSEDE_CLAIM MERGE_CLAIMS SUPERSEDE_LINK TASK_RESULT].freeze
  TASK_TYPES = %w[OPPOSING_EVIDENCE_SEARCH QUALIFIER_CHECK SOURCE_INDEPENDENCE_CHECK EVIDENCE_VERIFICATION].freeze

  module_function

  def reject(code, path, detail)
    raise Ledger::Rejected.new([ { code: code, path: path, detail: detail } ])
  end

  # --- revising -------------------------------------------------------------

  def revise_claim(token, claim, text:, type: nil, reason: nil, topics: [], carry_links: true)
    payload = { "claim_id" => claim.id, "canonical_text" => text.to_s, "claim_type" => type.presence || claim.claim_type,
                "affirms_not_private_individual" => true, "qualifiers" => claim.qualifiers.presence || {}, "reason" => reason.presence }.compact
    result = Assistants::Write.call(token, "SUPERSEDE_CLAIM", payload)
    new_claim = Claim.find(Ledger::Ids.derive(result.contribution.id, "claim"))
    accepted = result.acceptance.present?
    carried = accepted && carry_links ? carry_links!(claim, new_claim) { |action, p| Assistants::Write.call(token, action, p) } : []
    Assistants::Write.call(token, "TAG_CLAIM", { "claim_id" => new_claim.id, "topics" => Array(topics) }) if accepted && Array(topics).any?
    { contribution: result.contribution, claim: new_claim, accepted: accepted, carried: carried }
  end

  def merge_claims(token, from, into, reason: nil)
    result = Assistants::Write.call(token, "MERGE_CLAIMS", { "from_claim_id" => from.id, "into_claim_id" => into.id, "reason" => reason.presence }.compact)
    { contribution: result.contribution, accepted: result.acceptance.present? }
  end

  def revise_link(token, link, direction:, strength: nil, steps: nil, reason: nil)
    payload = { "link_id" => link.id, "direction" => direction, "relevance_strength" => strength.presence || link.relevance_strength,
                "interpretive_steps" => (steps.nil? ? link.interpretive_steps : steps.to_i), "reason" => reason.presence }.compact
    result = Assistants::Write.call(token, "SUPERSEDE_LINK", payload)
    { contribution: result.contribution, accepted: result.acceptance.present?, link: EvidenceClaimLink.find_by(contribution_id: result.contribution.id) }
  end

  # Re-issues every counted link of the old claim onto its revision. The writer
  # is whoever affirms that the evidence bears the same way on the corrected text.
  def carry_links!(old_claim, new_claim)
    seq = Contribution.maximum(:seq)
    old_claim.evidence_claim_links.effective_at(seq).order(:created_seq).map do |link|
      payload = { "evidence_item_id" => link.evidence_item_id, "claim_id" => new_claim.id, "direction" => link.direction,
                  "relevance_strength" => link.relevance_strength, "interpretive_steps" => link.interpretive_steps,
                  "note" => "carried from link #{link.id} on the revision of claim #{old_claim.id}" }
      yield("LINK_EVIDENCE", payload)
      link.id
    end
  end

  # --- blind hand-off -------------------------------------------------------

  def open_task(token, claim, type:, location_id: nil)
    reject("SCHEMA_INVALID", "$.type", "expected one of #{TASK_TYPES.join(', ')}") unless TASK_TYPES.include?(type.to_s)
    location = nil
    if type == "EVIDENCE_VERIFICATION"
      reject("SCHEMA_INVALID", "$.location_id", "EVIDENCE_VERIFICATION needs the location_id of the passage to check (see get_claim's evidence)") if location_id.blank?
      location = SourceLocation.find_by(id: location_id) || reject("NOT_FOUND", "$.location_id", "no such source location")
    end
    Tasks::Lease.expire_stale!
    existing = Task.where(status: %w[OPEN LEASED], task_type: type, target_id: claim.id).order(:created_at).to_a
    existing = existing.select { |t| t.packet.dig("context", "source_location_id") == location.id } if location
    return { task: existing.first, created: false } if existing.any?

    seq = Contribution.maximum(:seq)
    domain = Topics.domain_for_claim(claim, seq) || Audits::Policy.default_domain
    task = Tasks::Create.call(task_type: type, target: claim, domain: domain, location: location, created_by: token.agent)
    { task: task, created: true }
  end

  # --- proposals ------------------------------------------------------------

  # Pending corrections on one claim, or on every claim whose principal is the given one.
  def proposals(claim: nil, principal: nil)
    Contribution.where(current_status: Contribution::PENDING, action_type: PROPOSAL_ACTIONS).order(:seq).filter_map do |c|
      claims = touched_claims(c)
      next if claims.empty?
      next if claim && claims.none? { |k| k.id == claim.id }
      next if principal && claims.none? { |k| principal_id_of(k) == principal.id }

      describe(c, claims)
    end
  end

  def touched_claims(c)
    p = c.payload || {}
    ids = case c.action_type
    when "SUPERSEDE_CLAIM" then [ p["claim_id"] ]
    when "MERGE_CLAIMS" then [ p["from_claim_id"], p["into_claim_id"] ]
    when "SUPERSEDE_LINK" then [ EvidenceClaimLink.find_by(id: p["link_id"])&.claim_id ]
    when "TASK_RESULT" then [ (t = Task.find_by(id: c.task_id)) && t.target_type == "CLAIM" ? t.target_id : nil ]
    else []
    end
    Claim.where(id: ids.compact).to_a
  end

  def describe(c, claims = touched_claims(c))
    p = c.payload || {}
    summary = case c.action_type
    when "SUPERSEDE_CLAIM" then "Revise to: #{p['canonical_text']}#{" (#{p['reason']})" if p['reason']}"
    when "MERGE_CLAIMS" then "Merge #{p['from_claim_id']} into #{p['into_claim_id']}#{" (#{p['reason']})" if p['reason']}"
    when "SUPERSEDE_LINK" then "Revise link #{p['link_id']} to #{p['direction']} #{p['relevance_strength']} with #{p['interpretive_steps']} steps#{" (#{p['reason']})" if p['reason']}"
    when "TASK_RESULT" then "Task result #{p['outcome']} with #{Array(p['ops']).size} items"
    end
    proposer = c.principal_contributor
    { contribution_id: c.id, kind: c.action_type, seq: c.seq, claim_ids: claims.map(&:id), claims: claims.map { |k| k.canonical_text.to_s[0, 160] },
      proposed_by: proposer.nil? || proposer.anonymous? ? "an anonymous contributor" : (proposer.display_name.presence || "a named contributor"),
      proposer_contributor_id: proposer&.id, summary: summary }
  end

  def principal_id_of(claim)
    c = claim.contribution
    c.principal_contributor_id || c.contributor_id
  end

  # Who may accept at the connector and on the page (stricter than the applier):
  # the principal of every touched claim, or anyone named where that principal is
  # anonymous, or a moderator. The applier still refuses the proposer's own principal.
  def may_accept?(principal, contribution)
    return false if principal.nil? || principal.anonymous?
    return true if Governance::Moderators.moderator?(principal)

    claims = touched_claims(contribution)
    return false if claims.empty?

    claims.all? do |claim|
      owner = Contributor.find_by(id: principal_id_of(claim))
      owner.nil? || owner.anonymous? || owner.id == principal.id
    end
  end

  # Appends ACCEPT through the given writer and, for a revised claim, carries the links.
  def accept!(contribution, principal:, carry_links: true)
    reject("NOT_ACCEPTABLE", "$.contribution_id", "this contribution is #{contribution.current_status.downcase}, not pending") unless contribution.current_status == Contribution::PENDING
    reject("NOT_AUTHORIZED", "$.contribution_id", "only the principal of the claims this touches (or anyone named, when that principal is anonymous, or a moderator) may accept it here") unless may_accept?(principal, contribution)

    result = yield("ACCEPT", { "contribution_id" => contribution.id })
    carried = []
    if carry_links && contribution.action_type == "SUPERSEDE_CLAIM"
      old_claim = Claim.find(contribution.payload["claim_id"])
      new_claim = Claim.find(Ledger::Ids.derive(contribution.id, "claim"))
      carried = carry_links!(old_claim, new_claim) { |action, payload| yield(action, payload) }
    end
    { contribution: result.contribution, carried: carried }
  end

  # --- status for cards and pages ------------------------------------------

  def status(claim, seq)
    superseded_by = claim.superseded_by_at(seq)
    merge = claim.merge_at(seq)
    revises = claim.supersedes_claim
    {
      status: claim.status_at(seq),
      revises: revises && { claim_id: revises.id, text: revises.canonical_text, reason: claim.contribution.payload&.dig("reason") },
      superseded_by: superseded_by && { claim_id: superseded_by.id, text: superseded_by.canonical_text, seq: superseded_by.created_seq,
                                        reason: superseded_by.contribution.payload&.dig("reason"), by: describe_principal(superseded_by.contribution) },
      merged_into: merge && { claim_id: merge.into_claim_id, seq: merge.created_seq },
      pending_proposals: proposals(claim: claim).size
    }
  end

  def describe_principal(contribution)
    p = contribution.principal_contributor
    p.nil? || p.anonymous? ? "an anonymous contributor" : (p.display_name.presence || "a named contributor")
  end
end
