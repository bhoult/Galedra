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
      # The counted links, once. Two things below want them — the retrieval
      # labels want each one's source location, the anonymous-provisional test
      # wants each one's contributor — and asking separately fetched the same
      # rows twice and preloaded the same evidence items twice
      # (docs/profiler/2026-09-19-weaknesses-at-3000-claims.md, finding 5).
      counted = claim.evidence_claim_links.counted_at(seq)
                     .includes(contribution: :contributor, evidence_item: :source_location).to_a
      # The effective set is the counted one minus the links a counted link
      # supersedes — exactly what the effective_at scope's NOT IN subquery says
      # — derived here so those rows and their evidence items are fetched once
      # rather than again by the main issue.
      superseded = counted.filter_map(&:supersedes_link_id).to_set
      effective = counted.reject { |l| superseded.include?(l.id) }.sort_by(&:created_seq)
      card = {
        headline: Headline.for(result.assessment_state),
        independent_lineages: lineages,
        review_checks: DisplayRules.checks_count(checks),
        stability: result.stability,
        main_issue: MainIssue.call(claim, seq, result, effective),
        labels: DisplayRules.for_result(result, anonymous: anonymous_provisional?(counted, seq)),
        related: related(claim, seq, model),
        plain: Plain.call(claim, seq, model, result),
        model: model.full_name, snapshot_seq: seq,
        # The number in the one form the display rules allow (06 §4 rule 2, CLAUDE.md
        # vocabulary): with its model and snapshot, never as "N% true". Nil when
        # the state carries no probability.
        stated: DisplayRules.stated(result.probability, model.full_name, seq)
      }
      card[:reason] = Headline.reason_text(result.not_applicable_reason) if result.assessment_state == "NOT_APPLICABLE"
      card[:labels] += retrieval_labels(counted, seq)
      card
    end

    # Stage 17: what Galedra's own fetch found for the quoted passages behind the
    # counted evidence. A fact for the reader and for auditors, not a score input.
    def retrieval_labels(counted, seq)
      locations = counted.filter_map { |link| link.evidence_item&.source_location }
      # One lookup per distinct source rather than one per link: four links
      # quoting one source asked the same question four times
      # (docs/profiler/2026-09-19-weaknesses-at-3000-claims.md, finding 5).
      latest = locations.map(&:source_id).uniq.index_with { |id| SourceRetrieval.latest_for(id, seq) }
      findings = locations.filter_map { |location| latest[location.source_id]&.finding_for(location.id) }
      labels = []
      labels << "A quoted passage was not found on the page when Galedra fetched it." if findings.include?("NOT_FOUND")
      # Said separately from NOT_FOUND, because they are different facts and
      # sharing a sentence was the whole complaint: a primary source published as
      # a PDF read as a passage that could not be found.
      labels << "A quoted passage is in a document this server does not read, such as a PDF, so it has not been checked here." if findings.include?("NOT_READ")
      labels << "Every quoted passage was confirmed on the page when Galedra fetched it." if findings.any? && findings.all? { |f| %w[VERBATIM NORMALIZED].include?(f) }
      labels
    end

    # A counted, unconfirmed link whose principal is anonymous (Stage 12).
    def anonymous_provisional?(counted, seq)
      counted.any? do |link|
        link.contribution.principal_contributor&.anonymous? && !Audits::Status.confirmed?(link.contribution_id, seq)
      end
    end

    def related(claim, seq, model)
      edges = claim.counted_incoming_edges(seq).map { |e| [ e.from_claim, e.relationship_type, "incoming" ] } +
              claim.counted_outgoing_edges(seq).map { |e| [ e.to_claim, e.relationship_type, "outgoing" ] }
      edges.map do |other, type, dir|
        state = Governance::Quarantines.live_for("CLAIM", other.id) ? "QUARANTINED" : Scoring::Score.call(other, seq, model).assessment_state
        { claim_id: other.id, relation: type, direction: dir, headline: Headline.for(state) }
      end
    end
  end
end
