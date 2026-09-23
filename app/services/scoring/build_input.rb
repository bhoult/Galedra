# frozen_string_literal: true

module Scoring
  # Builds the scorer input (spec 11 §12) for a claim as of a snapshot seq:
  # counted links (03 §4 Step 1: accepted, active, not superseded, with an
  # active evidence item and location, and no live quarantine on the source),
  # evidence facts as of that seq, audit state, and task-derived checks.
  module BuildInput
    module_function

    # The same, for many (claim, seq) pairs, from one load per table
    # (Scoring::BuildInputBatch). {claim_id => input}.
    def call_many(pairs)
      return {} if pairs.empty?

      BuildInputBatch.call(pairs)
    end

    def call(claim, seq)
      evaluable, reason = claim.evaluability_at(seq)
      {
        "claim" => { "id" => claim.id, "type" => claim.claim_type, "truth_evaluable" => evaluable, "not_evaluable_reason" => reason },
        "snapshot_seq" => seq,
        "links" => links_for(claim, seq, own_origins(claim, seq), other_editions(claim, seq)),
        "task_checks" => Tasks::Checks.for(claim.id, seq)
      }
    end

    # The origins this claim was taken out of: the sources of the sections it is
    # placed in. Evidence from one of them establishes that the claim quotes its
    # source faithfully, which is provenance and not corroboration (Stage 35).
    def own_origins(claim, seq)
      section_ids = ClaimPlacement.counted_at(seq).where(claim_id: claim.id).pluck(:section_id).compact.uniq
      return Set.new if section_ids.empty?

      Source.where(id: Section.where(id: section_ids).distinct.pluck(:source_id))
            .filter_map { |source| Sources::Origin.key_for(source) }.to_set
    end

    # The other editions of the source this claim says it is about.
    #
    # `qualifiers.source_edition` names one source — one version of a document —
    # and the spec has named that qualifier since 02 §3.3. A reading of a
    # different version in the same lineage is a reading of a different text,
    # which is how two readings of a page taken twelve days after the event
    # came to be counted as contradicting a claim about what it said on the day
    # (Stage 41, claim 0491ac36).
    #
    # Empty, and free, for every claim that names no edition — which is all of
    # them until someone says otherwise. Lineage is `lineage_key` where the
    # sources carry one, and the `previous_version_id` chain either way.
    # Windowed at the seq, like every other input in this module. Without it a
    # source appended later joined the lineage retroactively and changed what
    # `BuildInput.call(claim, 50)` returned today versus yesterday — the same
    # seq and model no longer producing a byte-identical trace, which is
    # Invariant 4 and the thing replay and a pinned snapshot both rest on
    # (code review, 2026-09-22).
    def other_editions(claim, seq)
      named_id = claim.qualifiers.is_a?(Hash) ? claim.qualifiers["source_edition"] : nil
      return Set.new if named_id.blank?

      named = Source.active_at(seq).find_by(id: named_id)
      return Set.new if named.nil?

      lineage = Source.active_at(seq)
      ids = lineage.where(previous_version_id: named.id).pluck(:id)
      ids << named.previous_version_id if named.previous_version_id
      ids += lineage.where(lineage_key: named.lineage_key).where.not(id: named.id).pluck(:id) if named.lineage_key.present?
      (ids.compact - [ named.id ]).to_set
    end

    # In a scoring pass the live quarantines for the whole set were loaded once
    # (Scoring::Pass); outside one this is the same existence check as before.
    # Membership of a set, so there is no ordering for batching to change.
    def quarantined?(source_id, seq)
      quarantined = Pass.quarantined_sources(seq)
      return quarantined.include?(source_id) if quarantined

      Governance::Quarantines.quarantined_at?("SOURCE", source_id, seq)
    end

    def links_for(claim, seq, own_origins = Set.new, other_editions = Set.new)
      # :contribution too, because the audit checks below ask every link for it
      # and loading them one at a time was the single largest source of queries
      # in a whole-graph pass (Stage 26).
      links = claim.evidence_claim_links.effective_at(seq)
                   .includes(:contribution, evidence_item: { source_location: :source }).order(:id)
      link_entries(links, seq, own_origins, other_editions) { |item| item.independence_group_at(seq)&.id }
    end

    # The entries for links already chosen as effective at seq and in id order.
    # The block answers an item's independence group, so a batch can answer it
    # from one load while a single call asks the database.
    def link_entries(links, seq, own_origins, other_editions, &group_id)
      links.filter_map do |link|
        item = link.evidence_item
        location = item.source_location
        next unless item.active_at?(seq) && location.active_at?(seq) && location.source.active_at?(seq)
        next if quarantined?(location.source_id, seq)
        next if Audits::Status.challenged?(link.contribution, seq)

        origin = Sources::Origin.key_for(location.source)
        {
          "id" => link.id, "evidence_id" => item.id, "direction" => link.direction,
          "self_referential" => own_origins.include?(origin),
          # A reading of a different version of the document this claim names.
          # Inert unless the model says what to do with it (Scoring::Calculate).
          "different_edition" => other_editions.include?(location.source_id),
          "relevance_strength" => link.relevance_strength, "interpretive_steps" => link.interpretive_steps,
          "created_seq" => link.created_seq,
          "audit_confirmed" => Audits::Status.confirmed?(link.contribution_id, seq),
          "evidence" => {
            "observation_type" => item.observation_type,
            "independence_group_id" => group_id.call(item),
            "origin" => origin,
            "passage" => location.excerpt_hash.presence || "location:#{location.id}",
            "source_type" => location.source.source_type,
            "assessment" => item.assessment,
            "created_seq" => item.created_seq
          }
        }
      end
    end
  end
end
