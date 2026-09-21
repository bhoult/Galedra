# frozen_string_literal: true

module Attribution
  # Everyone whose signed entry went into one piece of work: the keys that wrote
  # the claims, the sources, the evidence and the links, and the people those
  # keys acted for (owner request, 2026-09-21).
  #
  # The foot of a check names only whoever started it, which is the smaller half
  # of the answer — a check is usually written by one connector and then filled
  # in by others, and until now the page said nothing about them. This gathers
  # the whole set from the log, so the credit is derived rather than asserted.
  #
  # Every lookup here takes the whole collection. One query per table, never one
  # per claim: see CLAUDE.md, "One row at a time is the defect this codebase
  # keeps producing". `spec/services/attribution/participants_spec.rb` counts the
  # statements and fails if that stops being true.
  module Participants
    # What an action type means in the words a reader uses, for the "did" column.
    # Anything missing falls back to the type in lower case, which reads well
    # enough for the ones nobody has needed to soften.
    DID = {
      "CREATE_CLAIM" => "wrote a claim", "SUPERSEDE_CLAIM" => "corrected a claim",
      "CREATE_SOURCE" => "added a source", "CREATE_SOURCE_LOCATION" => "marked a passage",
      "RETRIEVE_SOURCE" => "fetched a source", "CREATE_EVIDENCE" => "recorded evidence",
      "LINK_EVIDENCE" => "linked evidence to a claim", "SUPERSEDE_LINK" => "revised a link",
      "CREATE_CLAIM_EDGE" => "related two claims", "MERGE_CLAIMS" => "merged duplicate claims",
      "CREATE_INDEPENDENCE_GROUP" => "named an independence group",
      "ASSIGN_INDEPENDENCE_GROUP" => "grouped evidence by lineage",
      "SET_TRUTH_EVALUABLE" => "ruled on whether a claim is checkable",
      "TAG_CLAIM" => "tagged a claim", "CREATE_SECTION" => "outlined the source",
      "PLACE_CLAIM" => "placed a claim in the outline", "CREATE_INFERENCE" => "drew an inference",
      "TASK_RESULT" => "answered a task", "AUDIT" => "audited an entry", "ACCEPT" => "accepted an entry",
      "INVALIDATE" => "invalidated an entry", "QUARANTINE" => "quarantined something",
      "RELEASE_QUARANTINE" => "released a quarantine", "TAKEDOWN" => "took content down"
    }.freeze

    # One party: a signing key, the person it acted for, and what it did here.
    Party = Struct.new(:agent, :principal, :entries, :did, :first_at, :last_at, keyword_init: true) do
      def for_someone_else? = principal && principal != agent
    end

    # The claims of a check, and everything that reached them.
    def self.for_claims(claim_ids, seeds: [])
      from(touching(claim_ids) + Array(seeds).compact)
    end

    # An outline: its sections as well, since the person who broke the source up
    # contributed to it as surely as whoever checked a claim inside it.
    def self.for_outline(root_id, claim_ids)
      from(touching(claim_ids) + Section.where(root_id: root_id).pluck(:contribution_id))
    end

    # Every contribution that produced a row bearing on these claims.
    def self.touching(claim_ids)
      ids = Array(claim_ids).compact.uniq
      return [] if ids.empty?

      found = Claim.where(id: ids).pluck(:contribution_id)
      found += ClaimTopic.where(claim_id: ids).pluck(:contribution_id)
      found += ClaimPlacement.where(claim_id: ids).pluck(:contribution_id)
      found += ClaimEvaluabilitySetting.where(claim_id: ids).pluck(:contribution_id)
      found += ClaimEdge.where(from_claim_id: ids).or(ClaimEdge.where(to_claim_id: ids)).pluck(:contribution_id)
      found += ClaimMerge.where(from_claim_id: ids).or(ClaimMerge.where(into_claim_id: ids)).pluck(:contribution_id)
      found += Inference.where(conclusion_claim_id: ids).pluck(:contribution_id)
      found += InferencePremise.where(claim_id: ids).pluck(:contribution_id)
      found + evidence_chain(ids)
    end

    # Links, the evidence they point at, the passage it was read from, the source
    # that passage is in, and any fetch of that source: four steps, four queries.
    def self.evidence_chain(claim_ids)
      links = EvidenceClaimLink.where(claim_id: claim_ids).pluck(:contribution_id, :evidence_item_id)
      item_ids = links.map(&:last).uniq
      return links.map(&:first) if item_ids.empty?

      items = EvidenceItem.where(id: item_ids).pluck(:contribution_id, :source_location_id)
      found = links.map(&:first) + items.map(&:first) +
              IndependenceGroupAssignment.where(evidence_item_id: item_ids).pluck(:contribution_id)
      location_ids = items.map(&:last).compact.uniq
      return found if location_ids.empty?

      locations = SourceLocation.where(id: location_ids).pluck(:contribution_id, :source_id)
      source_ids = locations.map(&:last).compact.uniq
      found + locations.map(&:first) +
        Source.where(id: source_ids).pluck(:contribution_id) +
        SourceRetrieval.where(source_id: source_ids).pluck(:contribution_id)
    end

    # Contributions in, parties out. Audits of anything gathered count too: an
    # auditor who read a passage back contributed to the record's standing.
    def self.from(contribution_ids)
      ids = contribution_ids.compact.uniq
      return [] if ids.empty?

      ids |= Audit.where(target_contribution_id: ids).pluck(:contribution_id)
      rows = Contribution.where(id: ids)
                         .pluck(:contributor_id, :action_type, :received_at, Arel.sql("envelope->>'delegation_id'"))
      group(rows, principals(rows))
    end

    # An agent's principal is the delegation it signed under; a human or the
    # system is its own. Resolved for the whole set in one query, because
    # Contribution#principal_contributor asks the database once per row.
    def self.principals(rows)
      AgentDelegation.where(id: rows.filter_map(&:last).uniq).pluck(:id, :principal_contributor_id).to_h
    end

    def self.group(rows, by_delegation)
      people = Contributor.where(id: (rows.map(&:first) + by_delegation.values).compact.uniq).index_by(&:id)
      tally = Hash.new { |h, k| h[k] = { entries: 0, did: Hash.new(0), first: nil, last: nil } }
      rows.each do |contributor_id, action_type, at, delegation_id|
        agent = people[contributor_id]
        next if agent.nil?

        principal = agent.agent? ? people[by_delegation[delegation_id]] : agent
        cell = tally[[ agent.id, principal&.id ]]
        cell[:entries] += 1
        cell[:did][DID.fetch(action_type, action_type.downcase.tr("_", " "))] += 1
        cell[:first] = at if cell[:first].nil? || at < cell[:first]
        cell[:last] = at if cell[:last].nil? || at > cell[:last]
      end
      parties(tally, people)
    end

    def self.parties(tally, people)
      tally.map do |(agent_id, principal_id), cell|
        Party.new(agent: people[agent_id], principal: people[principal_id], entries: cell[:entries],
                  did: cell[:did].sort_by { |phrase, count| [ -count, phrase ] },
                  first_at: cell[:first], last_at: cell[:last])
      end.sort_by { |p| [ -p.entries, p.first_at ] }
    end

    private_class_method :touching, :evidence_chain, :principals, :group, :parties
  end
end
