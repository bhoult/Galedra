# frozen_string_literal: true

module Sections
  # How far an outline has come (Stage 22): leaves, leaves extracted (holding an
  # accepted claim, or whose extraction task is complete or cancelled), claims,
  # claims checked (with any counted evidence), and open work. Descriptive; no
  # score for the outline.
  module Progress
    module_function

    def call(root, seq)
      sections = Section.counted_at(seq).where(root_id: root.root_id).to_a
      parents = sections.map(&:parent_id).compact.to_set
      leaves = sections.reject { |s| parents.include?(s.id) }
      claim_ids = ClaimPlacement.counted_at(seq).where(section_id: sections.map(&:id)).pluck(:claim_id).uniq
      counted_claims = Claim.counted_at(seq).where(id: claim_ids).where.not(id: Governance::Quarantines.quarantined_claim_ids).pluck(:id)
      with_claims = ClaimPlacement.counted_at(seq).where(section_id: leaves.map(&:id), claim_id: counted_claims).distinct.pluck(:section_id).to_set
      settled = Task.where(task_type: "CLAIM_EXTRACTION", section_id: leaves.map(&:id), status: %w[COMPLETE CANCELLED]).distinct.pluck(:section_id).to_set
      extracted = leaves.count { |l| with_claims.include?(l.id) || settled.include?(l.id) }
      checked = EvidenceClaimLink.counted_at(seq).where(claim_id: counted_claims).distinct.count(:claim_id)
      open = Task.where(section_id: sections.map(&:id), status: %w[OPEN LEASED]).to_a.count { |t| t.open_slots.positive? }
      { leaves: leaves.size, leaves_extracted: extracted, claims: counted_claims.size, checked: checked, open_tasks: open }
        .merge(check_split(counted_claims, seq))
    end

    # Stage 34: how many claims carry a check by their own author, and how many
    # carry one by somebody else. Kept apart because only the second says anyone
    # independent has looked, and a first pass by one person makes the first
    # number large while the second stays at nought.
    #
    # Batched deliberately: a per-claim version of this runs on the share line of
    # an outline holding hundreds of claims.
    def check_split(claim_ids, seq)
      blank = { self_checked: 0, independently_checked: 0 }
      # Every task type, not only the checklist ones: EVIDENCE_VERIFICATION is
      # the most numerous check and is not a checklist item.
      claim_for_task = Task.where(target_type: "CLAIM", target_id: claim_ids).pluck(:id, :target_id).to_h
      return blank if claim_for_task.empty?

      results = Contribution.where(action_type: "TASK_RESULT", task_id: claim_for_task.keys).where("seq <= ?", seq)
                            .select { |r| Contributions::Standing.accepted_at?(r, seq) }
      return blank if results.empty?

      own_results = TaskAssignment.where(result_contribution_id: results.map(&:id), self_performed: true).pluck(:result_contribution_id).to_set
      by_author = Set.new
      by_others = Set.new
      results.each do |r|
        claim_id = claim_for_task[r.task_id]
        (own_results.include?(r.id) ? by_author : by_others) << claim_id
      end
      { self_checked: by_author.size, independently_checked: by_others.size }
    end

    # "N claims · N self-checked · N independently checked · <counts by state> ·
    # <url>" (Stage 22, 06 §6, and Stage 34 for the split).
    #
    # All three numbers, rather than the shorter "none independently checked":
    # this line is what a person pastes where they were going to post, so it
    # states the weakness in the same breath as the volume. It also still reads
    # correctly once the third number moves, which the short form does not.
    def share_line(root, seq, url)
      p = call(root, seq)
      counts = Tree.call(root, seq)[:counts]
      "Checked in Galedra: #{root.heading} · #{p[:claims]} claims · #{p[:self_checked]} self-checked · " \
        "#{p[:independently_checked]} independently checked · #{Tree.states_line(counts)} · #{url}"
    end

    # Roots whose leaves are all extracted but fewer than a quarter of whose claims have evidence (Article XXII).
    def unfinished(seq)
      Tree.roots(seq).filter_map do |root|
        p = call(root, seq)
        next if p[:claims].zero? || p[:leaves_extracted] < p[:leaves]
        next unless p[:checked] * 4 < p[:claims]

        [ root, p ]
      end
    end
  end
end
