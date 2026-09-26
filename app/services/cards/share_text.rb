# frozen_string_literal: true

module Cards
  # What a person pastes where they were going to post, for readers who have
  # never heard of Galedra (owner request, 2026-09-23). Three short lines:
  #
  #   Checked in Galedra: score 0.23, evidence mixed
  #   “The statement, or its opening words when it is long”
  #   https://…
  #
  # It replaced a line of counts, model names and snapshot numbers that was
  # exact and unreadable on Facebook. The exact form is one click away, on the
  # page the link opens. Two things stay, in plain words: a score is shown only
  # when there is one, and work nobody else has reviewed says so, because a
  # share that looks more checked than it is does the most harm (Stage 43 M4).
  module ShareText
    MAX_QUOTE = 200
    UNREVIEWED = "not yet reviewed by anyone else"

    module_function

    # label: a badge label ("Evidence mixed"). figure: a probability string, or
    # nil. quote: the statement, quoted. title: a heading, unquoted (an outline
    # is a source, not a statement). reviewed: false adds the caveat.
    def call(label:, url:, figure: nil, quote: nil, title: nil, reviewed: true)
      head = [ ("score #{short(figure)}" if figure), label.to_s.downcase ].compact.join(", ")
      head = "#{head} · #{UNREVIEWED}" unless reviewed
      lines = [ "Checked in Galedra: #{head}" ]
      lines << "“#{excerpt(quote)}”" if quote.present?
      lines << excerpt(title) if quote.blank? && title.present?
      lines << url.to_s
      lines.join("\n")
    end

    # For one claim, from its card.
    def for_claim(claim, card, url)
      call(label: Badge.for(card[:assessment_state], card[:probability])[:label], figure: card[:probability],
           quote: claim.canonical_text, url: url, reviewed: !card[:provisional])
    end

    # The first line without its prefix, for a link preview's description.
    def summary_line(text) = text.lines.first.to_s.delete_prefix("Checked in Galedra: ").strip.sub(/\A./, &:upcase)

    # Two places, half-even, like every other rounding here: 0.2346 → "0.23".
    def short(figure)
      Scoring::Decimal.fixed(BigDecimal(figure.to_s), 2)
    end

    def excerpt(text)
      text = text.to_s.squish
      return text if text.length <= MAX_QUOTE

      cut = text[0, MAX_QUOTE]
      cut = cut[0, cut.rindex(" ")] if cut.rindex(" ").to_i > MAX_QUOTE / 2
      "#{cut.sub(/[\s,;:.–—-]+\z/, '')}…"
    end
  end
end
