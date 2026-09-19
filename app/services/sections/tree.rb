# frozen_string_literal: true

module Sections
  # The counted tree under a root at a seq, with per-section counts (Stage 20).
  # No section, root, source, or speaker ever gets a probability, headline, or
  # badge: only counts by assessment state in the 06 §6 form, with its fixed
  # note. Claims appear only when accepted; proposals are a count.
  module Tree
    NOTE = "Counts depend on extraction granularity. There is never a score for a section, a source, or a speaker."
    STATES = %w[SUPPORTED LEANS_SUPPORTED UNRESOLVED LEANS_CONTRADICTED CONTRADICTED INSUFFICIENT_EVIDENCE NOT_APPLICABLE].freeze

    module_function

    # {section:, children: [...], claims: [claim...], pending: n, counts: {...}}
    def call(root, seq, model: Scoring::Registry.default_model, depth: nil)
      sections = Section.counted_at(seq).where(root_id: root.root_id).order(:depth, :position, :created_seq).to_a
      by_parent = sections.group_by(&:parent_id)
      placements = ClaimPlacement.active_at(seq).where(section_id: sections.map(&:id)).order(:position, :created_seq).to_a
      claims_by_id = Claim.where(id: placements.map(&:claim_id)).index_by(&:id)
      quarantined = Governance::Quarantines.quarantined_claim_ids.to_set
      states = {}
      node = lambda do |section, level|
        mine = placements.select { |p| p.section_id == section.id }
        counted = mine.select { |p| p.accepted_at?(seq) }.filter_map { |p| claims_by_id[p.claim_id] }.select { |c| c.counted_at?(seq) && !quarantined.include?(c.id) }
        pending = mine.count { |p| !p.accepted_at?(seq) }
        counted.each { |c| states[c.id] ||= model ? Scoring::Score.call(c, seq, model).assessment_state : nil }
        children = depth && level >= depth ? [] : by_parent.fetch(section.id, []).map { |child| node.call(child, level + 1) }
        counts = tally(counted.map { |c| states[c.id] })
        children.each { |ch| counts = merge(counts, ch[:counts]) }
        { section: section, children: children, claims: counted, states: counted.to_h { |c| [ c.id, states[c.id] ] }, pending: pending + children.sum { |ch| ch[:pending] }, counts: counts }
      end
      node.call(root, 0)
    end

    def tally(states)
      base = { "claims" => states.size, "checkable" => 0 }.merge(STATES.to_h { |s| [ s, 0 ] })
      states.compact.each do |s|
        base[s] += 1
        base["checkable"] += 1 unless s == "NOT_APPLICABLE" # truth-evaluable, per 06 §6
      end
      base
    end

    def merge(a, b) = a.merge(b) { |_, x, y| x + y }

    # "168 extracted claims · 131 truth-evaluable · 74 SUPPORTED …" (06 §6).
    def counts_line(counts)
      parts = [ "#{counts['claims']} claims", "#{counts['checkable']} checkable" ]
      STATES.each { |s| parts << "#{counts[s]} #{s.downcase.tr('_', ' ')}" if counts[s].positive? }
      parts.join(" · ")
    end

    # Only the states, in 06 §6 order: "74 supported · 21 leans supported · …".
    def states_line(counts)
      parts = STATES.filter_map { |s| "#{counts[s]} #{s.downcase.tr('_', ' ')}" if counts[s].positive? }
      parts.empty? ? "no claims yet" : parts.join(" · ")
    end

    # Sections holding a claim, as [{section, path}] at a seq.
    def placements_for(claim, seq)
      ClaimPlacement.counted_at(seq).where(claim_id: claim.id).includes(:section).map(&:section).select { |s| s.counted_at?(seq) }
    end

    def roots(seq)
      Section.counted_at(seq).where(parent_id: nil).order(created_seq: :desc)
    end
  end
end
