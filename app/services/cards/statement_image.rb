# frozen_string_literal: true

require "vips"

module Cards
  # The share card for a whole check (after Stage 19): what was asked, then
  # the plain headline per claim. Same paper, ink, and rules as Cards::Image.
  module StatementImage
    module_function

    def render(investigation, base_url: nil)
      seq = Contribution.maximum(:seq)
      model = Scoring::Registry.default_model
      claims = investigation.claims
      # Scored once, as a set, and handed to the cards and the verdict.
      results = Scoring::Score.call_many(claims, seq, model)
      canvas = (Vips::Image.black(Image::WIDTH, Image::HEIGHT) + Image::PAPER).cast("uchar").copy(interpretation: :srgb)
      canvas = canvas.draw_rect(Image::ACCENT, 0, 0, 14, Image::HEIGHT, fill: true)
      y = Image::MARGIN
      # Stage 45: while only an assistant's first reading exists, the card says
      # so where the headline goes, in words and never as a badge.
      reading = Investigations::Preliminary.reading(claims, results, Investigations::Preliminary.for_investigation(investigation, seq))
      eyebrow = reading[:preliminary] ? "GALEDRA · PRELIMINARY · AN AI'S FIRST READING, NOT YET SOURCED" : "GALEDRA · CHECKED, NOT SETTLED"
      canvas, y = Image.stamp(canvas, eyebrow, "sans 20", Image::MUTED, y)
      asked = investigation.statement.presence || claims.first&.canonical_text
      canvas, y = Image.stamp(canvas, "“#{Image.truncate(asked, 200)}”", "serif bold 40", Image::INK, y + 12)
      if reading[:preliminary]
        canvas, = Image.stamp(canvas, "Preliminary: #{reading[:phrase]}", "sans 34", Image::ACCENT, y + 18)
        footer = "#{claims.size} #{'claim'.pluralize(claims.size)} · being checked against sources#{" · #{base_url}" if base_url}"
        canvas, = Image.stamp(canvas, footer, "sans 18", Image::MUTED, Image::HEIGHT - Image::MARGIN - 24)
        return canvas.write_to_buffer(".png")
      end
      cards = claims.map { |c| Cards::ClaimCard.call(c, seq, model, results[c.id]) }
      verdict = Investigations::Verdict.call(claims, seq, model, results: results)
      summary = Investigation.summary(cards, verdict)
      canvas, y = Image.stamp(canvas, summary[:headline], "sans 34", Image::ACCENT, y + 18)
      canvas, y = Image.stamp(canvas, "#{summary[:detail]}.", "sans 24", Image::INK, y + 8) if summary[:detail].present?
      canvas, y = Image.stamp(canvas, summary[:stated], "sans 20", Image::MUTED, y + 6) if summary[:stated]
      say = cards.size == 1 && cards.first[:plain][:say_instead]
      canvas, y = Image.stamp(canvas, "Say instead: #{Image.truncate(say, 180)}", "sans italic 26", Image::INK, y + 12) if say
      footer = "#{claims.size} #{'claim'.pluralize(claims.size)} · #{model.full_name} at snapshot #{seq} · provisional until audited#{" · #{base_url}" if base_url}"
      canvas, = Image.stamp(canvas, footer, "sans 18", Image::MUTED, Image::HEIGHT - Image::MARGIN - 24)
      canvas.write_to_buffer(".png")
    end
  end
end
