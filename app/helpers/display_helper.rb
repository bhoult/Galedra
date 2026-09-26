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

  # `ledger-default@0.1.0` looks enough like an email address that Cloudflare's
  # obfuscation rewrites it to "[email protected]" in the tunnel, which makes
  # every model name on the page unreadable while the app serves it correctly.
  # The markers below are Cloudflare's own opt-out and are an ordinary HTML
  # comment to everything else.
  def model_name(name)
    return "" if name.blank?

    safe_join([ raw("<!--email_off-->"), name.to_s, raw("<!--/email_off-->") ]) # rubocop:disable Rails/OutputSafety
  end

  def seq_link(seq)
    link_to "seq #{seq}", contributions_path(after_seq: seq - 1, limit: 1)
  end

  # The LAST eight characters, not the first.
  #
  # Ids here are UUIDv7, whose leading 48 bits are a millisecond timestamp, so
  # eight hex characters off the front is 32 bits of that clock: everything
  # created inside roughly the same 65-second window shares it. Measured on the
  # dev node, all three determination threads shared one prefix and four of
  # eleven feature requests shared another — which is precisely the set of rows
  # someone is most likely to be comparing. The tail is random bits and does not
  # collide that way.
  #
  # Mcp::Server accepts either end when resolving a shortened id, so what is
  # printed here can be typed back.
  def short_id(id)
    text = id.to_s
    text.length > 8 ? text[-8..] : text
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

  # One character for a claim's state, for the tree's left column where a word
  # would not fit. The full state is the title attribute, and every page that
  # has room spells it out: this is a space constraint, not a new vocabulary.
  STATE_MARKS = { "SUPPORTED" => "++", "LEANS_SUPPORTED" => "+", "UNRESOLVED" => "~",
                  "LEANS_CONTRADICTED" => "-", "CONTRADICTED" => "--",
                  "INSUFFICIENT_EVIDENCE" => "?", "NOT_APPLICABLE" => "n/a" }.freeze

  def state_mark(state) = STATE_MARKS.fetch(state.to_s, "·")

  # A small validity badge for a set of claims (an outline section, an
  # investigation): the icon only, with what it means, what it was read from and
  # the figure on hover (owner request, 2026-09-23). `of` finishes "read from
  # the 12 claims ...".
  def reading_mark(verdict, of:)
    return "".html_safe if verdict.nil?

    tag.span(Cards::Badge.svg(verdict[:badge], size: 14), class: "reading-mark", title: Investigations::Verdict.title(verdict, of: of))
  end

  # The same icon for one claim, from its own state and probability.
  def claim_mark(result, model: nil, seq: nil)
    return tag.span("·", class: "reading-mark", title: "Not scored under any released model") if result.nil?

    badge = Cards::Badge.for(result.assessment_state, result.probability)
    figure = result.probability && [ result.probability, (" under #{model.full_name}" if model), (" at snapshot #{seq}" if seq) ].join
    tag.span(Cards::Badge.svg(badge[:key], size: 14), class: "reading-mark",
                                                       title: [ "#{badge[:label]} (#{result.assessment_state})", figure, "provisional until audited" ].compact.join(" · "))
  end

  # The figure beside a heading in an outline tree, small and muted, with what
  # it is on hover. Nothing when the section has too little scored to have one.
  def tree_score(verdict)
    return "".html_safe unless verdict&.dig(:figure)

    tag.span(verdict[:figure], class: "tree-score", title: "#{verdict[:stated]}. #{verdict[:note]}")
  end

  def tree_claim_score(result, model:, seq:)
    return "".html_safe unless result&.probability

    tag.span(result.probability, class: "tree-score", title: "#{result.probability} under #{model&.full_name} at snapshot #{seq}. Model-conditional, not a share of truth.")
  end

  # A claim's score, when it has one: the probability, with what it is
  # conditional on on hover. A state with too little evidence has none, and
  # says why rather than showing a blank.
  def score_cell(result, model:, seq:)
    return tag.span("no model", class: "muted") if result.nil?
    return tag.span("—", class: "muted", title: "No score: #{result.assessment_state} carries no probability") if result.probability.nil?

    tag.span(result.probability, class: "score", title: "#{result.probability} under #{model&.full_name} at snapshot #{seq}. Model-conditional, not a share of truth.")
  end
end
