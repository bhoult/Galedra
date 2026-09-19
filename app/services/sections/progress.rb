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
    end

    # "N claims recorded, M checked · <counts by state> · <url>" (Stage 22, 06 §6).
    def share_line(root, seq, url)
      p = call(root, seq)
      counts = Tree.call(root, seq)[:counts]
      "Checked in Galedra: #{root.heading} · #{p[:claims]} claims recorded, #{p[:checked]} checked · #{Tree.states_line(counts)} · #{url}"
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
