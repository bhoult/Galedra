# View-side wording for the display rules of spec 06 §4. The rules more than
# one surface needs live in Cards::DisplayRules, which this delegates to.
module DisplayHelper
  NO_NUMBER_STATES = %w[INSUFFICIENT_EVIDENCE NOT_APPLICABLE QUARANTINED].freeze

  def state_label(state)
    Cards::Headline.for(state)
  end

  # Rule 3: no number at all for INSUFFICIENT_EVIDENCE and NOT_APPLICABLE.
  # Rule 2: when shown, always with model and snapshot.
  def assessment_number(assessment)
    return nil if assessment.nil? || NO_NUMBER_STATES.include?(assessment[:assessment_state])

    Cards::DisplayRules.stated(assessment[:probability], assessment[:model], assessment[:snapshot_seq])
  end

  # Rule 5: review coverage is always a count of checks, never a percentage or low/medium/high.
  def review_checks_text(checklist)
    "Review checks: #{Cards::DisplayRules.checks_count(checklist)}"
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

  # Where in a source a passage sits, in words rather than as the JSON the
  # locator is stored as. A time range on a video is the common case and
  # "0:00–3:31" is what a reader expects; the stored form stays untouched,
  # because it is what the hash and the retrieval check are over.
  def locator_label(location)
    locator = location.locator || {}
    case location.locator_type
    when "TIME_RANGE" then "#{clock(locator['start'])}–#{clock(locator['end'])}"
    when "CHAR_RANGE" then "characters #{locator['start']}–#{locator['end']}"
    when "PAGE_RANGE" then "pages #{locator['start']}–#{locator['end']}"
    when "QUOTE", "TRANSCRIPTION" then location.locator_type.downcase
    else location.locator_type.to_s.downcase.tr("_", " ")
    end
  end

  # 00:03:31 reads as 3:31; an hour in, it keeps the hour.
  def clock(value)
    parts = value.to_s.split(":").map { |n| n.to_i }
    return value.to_s unless parts.size == 3

    h, m, sec = parts
    h.positive? ? format("%d:%02d:%02d", h, m, sec) : format("%d:%02d", m, sec)
  end
end
