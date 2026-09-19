# frozen_string_literal: true

module Cards
  # The compact answer card (spec 06 §3, §4): state in words, independent
  # lineages, review checks as a count, stability, the main issue, related
  # claims, and the labels the display rules require. No number here; the
  # number sits in the assessment block behind "Show calculation".
  module ClaimCard
    module_function

    def call(claim, seq, model, result = Scoring::Score.call(claim, seq, model))
      lineages = result.support_groups + result.contradict_groups
      checks = result.review_checklist
      card = {
        headline: Headline.for(result.assessment_state),
        independent_lineages: lineages,
        review_checks: "#{checks.count { |_, v| v['ok'] }} of #{checks.size}",
        stability: result.stability,
        main_issue: MainIssue.call(claim, seq, result),
        labels: labels(result, anonymous: anonymous_provisional?(claim, seq)),
        related: related(claim, seq, model),
        plain: Plain.call(claim, seq, model, result),
        model: model.full_name, snapshot_seq: seq,
        # The number in the one form the display rules allow (06 §4 rule 2, CLAUDE.md
        # vocabulary): with its model and snapshot, never as "N% true". Nil when
        # the state carries no probability.
        stated: (result.probability && "#{result.probability} under #{model.full_name} at snapshot #{seq}")
      }
      card[:reason] = Headline.reason_text(result.not_applicable_reason) if result.assessment_state == "NOT_APPLICABLE"
      card[:labels] += retrieval_labels(claim, seq)
      card
    end

    def labels(result, anonymous: false)
      labels = []
      labels << (anonymous ? "Not yet independently audited; some evidence was recorded by an anonymous contributor." : "Not yet independently audited.") if result.provisional
      labels << "Evidence points both ways." if result.contested
      labels << "This assessment depends heavily on modeling choices." if result.model_dependent
      checks = result.review_checklist
      done = checks.count { |_, v| v["ok"] }
      if %w[SUPPORTED CONTRADICTED].include?(result.assessment_state) && done <= 1
        labels << "Evidence reviewed so far #{result.assessment_state == 'SUPPORTED' ? 'supports' : 'contradicts'} this claim, but only #{done} of #{checks.size} review checks #{done == 1 ? 'has' : 'have'} been done."
      end
      labels
    end

    # Stage 17: what Galedra's own fetch found for the quoted passages behind the
    # counted evidence. A fact for the reader and for auditors, not a score input.
    def retrieval_labels(claim, seq)
      findings = claim.evidence_claim_links.counted_at(seq).includes(evidence_item: :source_location).filter_map do |link|
        location = link.evidence_item.source_location
        SourceRetrieval.latest_for(location.source_id, seq)&.finding_for(location.id)
      end
      labels = []
      labels << "A quoted passage was not found on the page when Galedra fetched it." if findings.include?("NOT_FOUND")
      labels << "Every quoted passage was confirmed on the page when Galedra fetched it." if findings.any? && findings.all? { |f| %w[VERBATIM NORMALIZED].include?(f) }
      labels
    end

    # A counted, unconfirmed link whose principal is anonymous (Stage 12).
    def anonymous_provisional?(claim, seq)
      claim.evidence_claim_links.counted_at(seq).includes(contribution: :contributor).any? do |link|
        link.contribution.principal_contributor&.anonymous? && !Audits::Status.confirmed?(link.contribution_id, seq)
      end
    end

    def related(claim, seq, model)
      edges = claim.incoming_edges.counted_at(seq).includes(:from_claim).map { |e| [ e.from_claim, e.relationship_type, "incoming" ] } +
              claim.outgoing_edges.counted_at(seq).includes(:to_claim).map { |e| [ e.to_claim, e.relationship_type, "outgoing" ] }
      edges.map do |other, type, dir|
        state = Governance::Quarantines.live_for("CLAIM", other.id) ? "QUARANTINED" : Scoring::Score.call(other, seq, model).assessment_state
        { claim_id: other.id, relation: type, direction: dir, headline: Headline.for(state) }
      end
    end
  end
end
