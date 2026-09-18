# frozen_string_literal: true

module Cards
  # The answer card's "main unresolved issue" (spec 06 §4 rule 5a), first match
  # wins: an invalidated or disputed audit; unreviewed independence; a QUALIFY
  # link; contested evidence; the first unmet review check; otherwise none.
  module MainIssue
    module_function

    def call(claim, seq, result)
      links = claim.evidence_claim_links.effective_at(seq).includes(:evidence_item)
      if (audit = disputed_audit(links, seq))
        return { kind: "DISPUTED_AUDIT", cites: [ "audit:#{audit.id}" ], text: "A verification of this claim's evidence was #{audit.invalidated? ? 'overturned' : 'left unresolved'} on audit" }
      end
      if result.independence_unreviewed.positive?
        return { kind: "INDEPENDENCE_UNREVIEWED", cites: [ "coverage:#{claim.id}" ], text: "#{result.independence_unreviewed} counted evidence item#{'s' if result.independence_unreviewed != 1} #{result.independence_unreviewed == 1 ? 'has' : 'have'} no independence review; repeats of one origin may be counted as several" }
      end
      if (qualify = links.find { |l| l.direction == "QUALIFY" })
        return { kind: "QUALIFY_LINK", cites: [ qualify.evidence_item_id ], text: qualify.evidence_item.statement.to_s }
      end
      return { kind: "CONTESTED", cites: links.select { |l| %w[SUPPORT CONTRADICT].include?(l.direction) }.map(&:evidence_item_id).uniq, text: "Evidence points both ways" } if result.contested

      unmet = result.review_checklist.find { |_, v| !v["ok"] }&.first
      return { kind: "REVIEW_CHECK_MISSING", cites: [ "coverage:#{claim.id}" ], text: "Review check not yet done: #{unmet.tr('_', ' ')}" } if unmet

      { kind: "NONE", cites: [], text: "none recorded" }
    end

    def disputed_audit(links, seq)
      ids = links.map(&:contribution_id)
      Audit.where(target_contribution_id: ids).where("created_seq <= ?", seq)
           .where("result = 'UNRESOLVED' OR invalidated_seq IS NOT NULL").order(:created_seq).first
    end
  end
end
