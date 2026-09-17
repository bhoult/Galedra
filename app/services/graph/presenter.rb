# frozen_string_literal: true

module Graph
  # JSON shapes for graph reads (spec 06 §2, §3). Everything is rendered as of a
  # snapshot seq; the assessment and card blocks arrive in Stages 6 and 9.
  module Presenter
    module_function

    def claim(claim, seq)
      evaluable, reason = claim.evaluability_at(seq)
      links = claim.evidence_claim_links.active_at(seq)
      counted = links.effective_at(seq)
      {
        id: claim.id, text: claim.canonical_text, type: claim.claim_type,
        truth_evaluable: evaluable, not_evaluable_reason: reason,
        status: claim.status_at(seq), qualifiers: claim.qualifiers, snapshot_seq: seq,
        created_seq: claim.created_seq, accepted_seq: claim.accepted_seq, invalidated_seq: claim.invalidated_seq,
        contribution_id: claim.contribution_id,
        supersedes_claim_id: claim.supersedes_claim_id, superseded_by_id: claim.superseded_by_at(seq)&.id,
        merged_into_id: claim.merge_at(seq)&.into_claim_id,
        evidence_counts: {
          support: counted.where(direction: "SUPPORT").count, contradict: counted.where(direction: "CONTRADICT").count,
          qualify: counted.where(direction: "QUALIFY").count, neutral: counted.where(direction: "NEUTRAL").count,
          counted: counted.count, pending: links.pending_at(seq).count
        },
        edges: {
          outgoing: claim.outgoing_edges.counted_at(seq).map { |e| edge(e) },
          incoming: claim.incoming_edges.counted_at(seq).map { |e| edge(e) }
        }
      }
    end

    def claim_evidence(claim, seq)
      links = claim.evidence_claim_links.active_at(seq).includes(evidence_item: { source_location: :source })
      {
        claim_id: claim.id, snapshot_seq: seq,
        counted: links.effective_at(seq).order(:created_seq).map { |l| link(l, seq, with_evidence: true) },
        pending: links.pending_at(seq).order(:created_seq).map { |l| link(l, seq, with_evidence: true) },
        superseded: links.counted_at(seq).where(id: links.counted_at(seq).where.not(supersedes_link_id: nil).select(:supersedes_link_id))
                         .order(:created_seq).map { |l| link(l, seq, with_evidence: false) }
      }
    end

    def link(link, seq, with_evidence: false)
      base = {
        id: link.id, direction: link.direction, relevance_strength: link.relevance_strength,
        interpretive_steps: link.interpretive_steps, note: link.note, evidence_item_id: link.evidence_item_id,
        claim_id: link.claim_id, supersedes_link_id: link.supersedes_link_id, superseded_by_id: link.superseded_by_at(seq)&.id,
        counted: link.effective_at?(seq), created_seq: link.created_seq, accepted_seq: link.accepted_seq,
        invalidated_seq: link.invalidated_seq, contribution_id: link.contribution_id
      }
      with_evidence ? base.merge(evidence: evidence(link.evidence_item, seq, with_links: false)) : base
    end

    def evidence(item, seq, with_links: true)
      base = {
        id: item.id, statement: item.statement, observation_type: item.observation_type,
        structured_value: item.structured_value, assessment: item.assessment,
        independence_group_id: item.independence_group_at(seq)&.id, active: item.active_at?(seq),
        created_seq: item.created_seq, invalidated_seq: item.invalidated_seq, contribution_id: item.contribution_id,
        source_location: location(item.source_location), source: source(item.source_location.source, with_content: false)
      }
      with_links ? base.merge(links: item.evidence_claim_links.active_at(seq).map { |l| link(l, seq) }) : base
    end

    def location(loc)
      {
        id: loc.id, source_id: loc.source_id, locator_type: loc.locator_type, locator: loc.locator,
        excerpt: loc.excerpt, excerpt_hash: loc.excerpt_hash, created_seq: loc.created_seq,
        invalidated_seq: loc.invalidated_seq, contribution_id: loc.contribution_id
      }
    end

    def source(source, with_content: true)
      base = {
        id: source.id, source_type: source.source_type, title: source.title, creator: source.creator,
        publisher: source.publisher, publication_date: source.publication_date, canonical_uri: source.canonical_uri,
        external_ids: source.external_ids, content_hash: source.content_hash, content_length: source.content_length,
        retrieved_at: source.retrieved_at, license: source.license, previous_version_id: source.previous_version_id,
        lineage_key: source.lineage_key, metadata: source.metadata, created_seq: source.created_seq,
        invalidated_seq: source.invalidated_seq, contribution_id: source.contribution_id
      }
      with_content ? base.merge(content: source.content) : base
    end

    def edge(edge)
      {
        id: edge.id, from_claim_id: edge.from_claim_id, to_claim_id: edge.to_claim_id,
        relationship_type: edge.relationship_type, created_seq: edge.created_seq, accepted_seq: edge.accepted_seq,
        invalidated_seq: edge.invalidated_seq, contribution_id: edge.contribution_id
      }
    end

    def contributor(contributor)
      {
        id: contributor.id, key_id: contributor.key_id, public_key: contributor.public_key, kind: contributor.kind,
        display_name: contributor.display_name, identity_tier: contributor.identity_tier,
        created_seq: contributor.created_seq, revoked_seq: contributor.revoked_seq, metadata: contributor.metadata,
        server_custodied: contributor.server_custodied?,
        contributions: contributor.contributions.group(:action_class).count
      }
    end
  end
end
