# frozen_string_literal: true

module Sections
  # The counted tree under a root at a seq, with per-section counts (Stage 20).
  # Claims appear only when accepted; proposals are a count.
  #
  # Each section also carries `verdict`: the reading of every claim under it,
  # on the same scale as an investigation (Investigations::Verdict), read by
  # proportion because a section is a collection of separate statements, with
  # a figure only when every checkable claim
  # under it has a probability. Until 2026-09-23 no section had one, by 06 §6;
  # the owner asked for a badge and a figure at every level of an outline, and
  # 06 §6 now says what that reading is and what it never is: a score for the
  # speaker or the source (Article XVIII).
  module Tree
    NOTE = "Counts depend on extraction granularity. The badge on a section reads the claims filed under it, and is never a score for the speaker or the source."
    STATES = %w[SUPPORTED LEANS_SUPPORTED UNRESOLVED LEANS_CONTRADICTED CONTRADICTED INSUFFICIENT_EVIDENCE NOT_APPLICABLE].freeze

    module_function

    # {section:, children: [...], claims: [claim...], pending: n, counts: {...}}
    def call(root, seq, model: Scoring::Registry.default_model, depth: nil)
      sections = Section.counted_at(seq).where(root_id: root.root_id).order(:depth, :position, :created_seq).to_a
      by_parent = sections.group_by(&:parent_id)
      placements = ClaimPlacement.active_at(seq).where(section_id: sections.map(&:id)).order(:position, :created_seq).to_a
      claims_by_id = Claim.where(id: placements.map(&:claim_id)).index_by(&:id)
      quarantined = Governance::Quarantines.quarantined_claim_ids.to_set
      # Every claim in the subtree is scored once, in one pass. Scoring per claim
      # inside the walk below was an N+1 that grew with the outline: a two-hour
      # transcript reached 255 claims, and this is called on every page view.
      all_claims = placements.filter_map { |p| claims_by_id[p.claim_id] }.select { |c| c.counted_at?(seq) && !quarantined.include?(c.id) }.uniq
      scored = model ? Scoring::Score.call_many(all_claims, seq, model) : {}
      states = all_claims.to_h { |c| [ c.id, model ? scored[c.id]&.assessment_state : nil ] }

      # `depth` truncates what is *rendered*, never what is counted. Counting only
      # the loaded children meant a branch reported the claims it held directly —
      # which is none, since claims live on leaves — so an outline asked for at a
      # shallower depth than it is deep reported zero at every level, root
      # included. Reported by an assistant through report_bug on a 255-claim
      # outline; see docs/experiments/2026-09-19-live-connector-outline.md.
      node = lambda do |section, level|
        mine = placements.select { |p| p.section_id == section.id }
        counted = mine.select { |p| p.accepted_at?(seq) }.filter_map { |p| claims_by_id[p.claim_id] }.select { |c| c.counted_at?(seq) && !quarantined.include?(c.id) }
        pending = mine.count { |p| !p.accepted_at?(seq) }
        subtree = by_parent.fetch(section.id, []).map { |child| node.call(child, level + 1) }
        counts = tally(counted.map { |c| states[c.id] })
        subtree.each { |ch| counts = merge(counts, ch[:counts]) }
        results = counted.filter_map { |c| scored[c.id] } + subtree.flat_map { |ch| ch[:results] }
        { section: section, children: depth && level >= depth ? [] : subtree, claims: counted,
          states: counted.to_h { |c| [ c.id, states[c.id] ] },
          scores: counted.to_h { |c| [ c.id, scored[c.id] ] },
          results: results,
          verdict: model && results.any? ? Investigations::Verdict.summarize(results, seq, model, collection: true) : nil,
          pending: pending + subtree.sum { |ch| ch[:pending] }, counts: counts }
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

    # The reading of a node for the API and MCP: what the page shows as a small
    # badge, in words. Nil when nothing under it has been scored.
    def reading(node)
      v = node[:verdict]
      return nil if v.nil?

      { badge: v[:badge].to_s, label: Cards::Badge.for_key(v[:badge])[:label], headline: v[:headline], sentence: v[:sentence],
        figure: v[:figure], stated: v[:stated], note: "A reading of the claims under this section, never a score for the speaker or the source." }.compact
    end

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
