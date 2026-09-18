# frozen_string_literal: true

require "vips"

module Cards
  # The share card as a 1200×630 PNG (Stage 14): the plain headline, the
  # claim, what to say instead, and the model and snapshot in small print.
  # No number, no colour coding of correctness (06 §4 rule 12).
  module Image
    WIDTH = 1200
    HEIGHT = 630
    MARGIN = 64
    PAPER = [ 246, 244, 238 ].freeze
    INK = [ 30, 29, 26 ].freeze
    MUTED = [ 106, 103, 95 ].freeze
    ACCENT = [ 44, 90, 134 ].freeze

    module_function

    def render(claim, seq, model, card = Cards::ClaimCard.call(claim, seq, model))
      canvas = (Vips::Image.black(WIDTH, HEIGHT) + PAPER).cast("uchar").copy(interpretation: :srgb)
      canvas = canvas.draw_rect(ACCENT, 0, 0, 14, HEIGHT, fill: true)
      y = MARGIN
      canvas, y = stamp(canvas, "GALEDRA · CHECKED, NOT SETTLED", "sans 20", MUTED, y)
      canvas, y = stamp(canvas, card[:plain][:headline], "serif bold 54", INK, y + 12)
      canvas, y = stamp(canvas, "“#{truncate(claim.canonical_text, 220)}”", "sans 30", INK, y + 20)
      canvas, y = stamp(canvas, "Say instead: #{truncate(card[:plain][:say_instead], 200)}", "sans italic 26", ACCENT, y + 14) if card[:plain][:say_instead]
      footer = "#{card[:review_checks]} review checks · #{card[:headline]} under #{model.full_name} at snapshot #{seq} · provisional until audited"
      canvas, = stamp(canvas, footer, "sans 18", MUTED, HEIGHT - MARGIN - 24)
      canvas.write_to_buffer(".png")
    end

    def stamp(canvas, text, font, colour, y)
      return [ canvas, y ] if text.blank? || y > HEIGHT - MARGIN

      mask = Vips::Image.text(escape(text), font: font, width: WIDTH - MARGIN * 2 - 14, dpi: 72, wrap: :word)
      mask = mask.crop(0, 0, mask.width, [ mask.height, HEIGHT - MARGIN - y ].min) if y + mask.height > HEIGHT - MARGIN
      layer = mask.new_from_image(colour).bandjoin(mask).cast("uchar").copy(interpretation: :srgb)
      [ canvas.composite2(layer, :over, x: MARGIN + 14, y: y), y + mask.height ]
    end

    def escape(text) = text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

    def truncate(text, max)
      text = text.to_s
      text.length > max ? "#{text[0, max - 1].rstrip}…" : text
    end
  end
end
