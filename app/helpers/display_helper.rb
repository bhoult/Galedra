# The normative display rules (spec 06 §4), in one place and unit-tested.
module DisplayHelper
  NO_NUMBER_STATES = %w[INSUFFICIENT_EVIDENCE NOT_APPLICABLE QUARANTINED].freeze

  def state_label(state)
    Cards::Headline.for(state)
  end

  # Rule 3: no number at all for INSUFFICIENT_EVIDENCE and NOT_APPLICABLE.
  # Rule 2: when shown, always with model and snapshot.
  def assessment_number(assessment)
    return nil if assessment.nil? || NO_NUMBER_STATES.include?(assessment[:assessment_state]) || assessment[:probability].nil?

    "#{assessment[:probability]} under #{assessment[:model]} at snapshot #{assessment[:snapshot_seq]}"
  end

  # Rule 5: review coverage is always a count of checks, never a percentage or low/medium/high.
  def review_checks_text(checklist)
    "Review checks: #{checklist.count { |_, v| v['ok'] }} of #{checklist.size}"
  end

  # Rule 4, 6: labels shown beside the state.
  def assessment_labels(assessment)
    labels = []
    labels << "Not yet independently audited." if assessment[:provisional]
    labels << "Evidence points both ways." if assessment[:contested]
    labels << "This assessment depends heavily on modeling choices." if assessment[:model_dependent]
    labels
  end

  # Rule 7: raw and independent counts together.
  def evidence_counts_text(raw, lineages)
    "#{pluralize(raw, 'source')}, #{pluralize(lineages, 'independent lineage')}"
  end

  # Rule 10: NOT_APPLICABLE explains itself in plain words.
  def not_applicable_text(reason)
    Cards::Headline.reason_text(reason)
  end

  def seq_link(seq)
    link_to "seq #{seq}", contributions_path(after_seq: seq - 1, limit: 1)
  end

  def short_id(id)
    id.to_s[0, 8]
  end

  # A contributor-supplied URI is linked only when it is http or https;
  # anything else is shown as text.
  def safe_source_link(uri)
    parsed = URI.parse(uri.to_s)
    return uri.to_s unless parsed.is_a?(URI::HTTP)

    link_to uri.to_s, parsed.to_s, rel: "nofollow noopener", target: "_blank"
  rescue URI::InvalidURIError
    uri.to_s
  end
end
