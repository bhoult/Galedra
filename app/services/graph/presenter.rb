# frozen_string_literal: true

module Graph
  # JSON shapes for graph reads (spec 06 §2, §3). Everything is rendered as of a
  # snapshot seq; the assessment and card blocks arrive in Stages 6 and 9.
  module Presenter
    module_function

    def claim(claim, seq, model: nil)
      if (quarantine = Governance::Quarantines.live_for("CLAIM", claim.id))
        return claim_stub(claim, seq, quarantine)
      end

      model ||= Scoring::Registry.default_model
      evaluable, reason = claim.evaluability_at(seq)
      links = claim.evidence_claim_links.active_at(seq)
      counted = links.effective_at(seq)
      {
        id: claim.id, text: claim.canonical_text, type: claim.claim_type,
        truth_evaluable: evaluable, not_evaluable_reason: reason,
        status: claim.status_at(seq), qualifiers: claim.qualifiers, snapshot_seq: seq, redacted: claim.redacted?,
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
        },
        assessment: model && assessment(Scoring::Score.call(claim, seq, model), seq, model),
        card: model && Cards::ClaimCard.call(claim, seq, model)
      }
    end

    # The assessment block (spec 06 §3): always with snapshot and model.
    def assessment(result, seq, model)
      {
        snapshot_seq: seq, model: model.full_name, assessment_state: result.assessment_state,
        probability: result.probability, model_dependent: result.model_dependent, stability: result.stability,
        review_coverage: result.review_coverage, review_checklist: result.review_checklist,
        support_groups: result.support_groups, contradict_groups: result.contradict_groups,
        independence_unreviewed: result.independence_unreviewed, contested: result.contested,
        provisional: result.provisional, not_applicable_reason: result.not_applicable_reason, trace_hash: result.trace_hash
      }
    end

    # The public stub that stays at a quarantined claim's URL (spec 05 §13).
    def claim_stub(claim, seq, quarantine)
      {
        id: claim.id, text: nil, type: claim.claim_type, status: "QUARANTINED", snapshot_seq: seq,
        created_seq: claim.created_seq, contribution_id: claim.contribution_id, redacted: claim.redacted?
      }.merge(Governance::Quarantines.stub(quarantine))
    end

    def claim_evidence(claim, seq)
      if (quarantine = Governance::Quarantines.live_for("CLAIM", claim.id))
        return { claim_id: claim.id, snapshot_seq: seq, counted: [], pending: [], superseded: [] }.merge(Governance::Quarantines.stub(quarantine))
      end

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
      withheld = Governance::Quarantines.evidence_withheld?(item)
      base = {
        id: item.id, statement: withheld ? nil : item.statement, observation_type: item.observation_type,
        structured_value: withheld ? nil : item.structured_value, assessment: item.assessment, withheld: withheld,
        redacted: item.redacted?,
        independence_group_id: item.independence_group_at(seq)&.id, active: item.active_at?(seq),
        created_seq: item.created_seq, invalidated_seq: item.invalidated_seq, contribution_id: item.contribution_id,
        source_location: location(item.source_location), source: source(item.source_location.source, with_content: false)
      }
      with_links ? base.merge(links: item.evidence_claim_links.active_at(seq).map { |l| link(l, seq) }) : base
    end

    def location(loc)
      withheld = Governance::Quarantines.live_for("SOURCE", loc.source_id).present?
      {
        id: loc.id, source_id: loc.source_id, locator_type: loc.locator_type, locator: withheld ? nil : loc.locator,
        excerpt: withheld ? nil : loc.excerpt, excerpt_hash: loc.excerpt_hash, withheld: withheld,
        redacted: loc.redacted_by_seq.present?, created_seq: loc.created_seq,
        invalidated_seq: loc.invalidated_seq, contribution_id: loc.contribution_id
      }
    end

    def source(source, with_content: true)
      if (quarantine = Governance::Quarantines.live_for("SOURCE", source.id))
        return {
          id: source.id, source_type: source.source_type, title: nil, content: nil, content_hash: source.content_hash,
          created_seq: source.created_seq, contribution_id: source.contribution_id, redacted: source.redacted?
        }.merge(Governance::Quarantines.stub(quarantine))
      end

      base = {
        id: source.id, source_type: source.source_type, title: source.title, creator: source.creator,
        publisher: source.publisher, publication_date: source.publication_date, canonical_uri: source.canonical_uri,
        external_ids: source.external_ids, content_hash: source.content_hash, content_length: source.content_length,
        retrieved_at: source.retrieved_at, license: source.license, previous_version_id: source.previous_version_id,
        lineage_key: source.lineage_key, metadata: source.metadata, created_seq: source.created_seq,
        invalidated_seq: source.invalidated_seq, contribution_id: source.contribution_id, redacted: source.redacted?
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
