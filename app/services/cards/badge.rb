# frozen_string_literal: true

module Cards
  # Ten validity badges for the check page's claim-by-claim section (owner
  # decision, after Stage 19, departing from 06 §4 rule 12 for that surface
  # only): a level from the claim's state and probability, a label in the
  # ledger's evidence wording, a colour from green through amber to red, and a
  # glyph. Never "true" or "false" (Article XXII).
  module Badge
    LEVELS = {
      strongly_supported: { label: "Strongly supported", color: "#1b7f3b", glyph: :double_check },
      mostly_supported:   { label: "Mostly supported",   color: "#3f9d4a", glyph: :check },
      leans_supported:    { label: "Leans supported",    color: "#7bb661", glyph: :check_outline },
      mixed:              { label: "Evidence mixed",     color: "#c9a227", glyph: :tilde },
      leans_against:      { label: "Leans against",      color: "#e08a2c", glyph: :cross_outline },
      mostly_against:     { label: "Mostly against",     color: "#d9532b", glyph: :cross },
      strongly_against:   { label: "Strongly against",   color: "#b3261e", glyph: :double_cross },
      not_checked:        { label: "Not checked yet",    color: "#8a8f98", glyph: :question },
      not_checkable:      { label: "Not a checkable fact", color: "#6f7480", glyph: :quote },
      withheld:           { label: "Withheld by moderation", color: "#55595f", glyph: :lock }
    }.freeze

    module_function

    # The level from the assessment state, split by probability where the state is wide.
    def level_for(state, probability)
      p = probability && BigDecimal(probability.to_s)
      case state
      when "SUPPORTED" then p && p >= BigDecimal("0.9") ? :strongly_supported : :mostly_supported
      when "LEANS_SUPPORTED" then :leans_supported
      when "UNRESOLVED" then :mixed
      when "LEANS_CONTRADICTED" then :leans_against
      when "CONTRADICTED" then p && p <= BigDecimal("0.1") ? :strongly_against : :mostly_against
      when "NOT_APPLICABLE" then :not_checkable
      when "QUARANTINED" then :withheld
      else :not_checked
      end
    end

    def for(state, probability)
      for_key(level_for(state, probability))
    end

    def for_key(key)
      LEVELS.fetch(key.to_sym).merge(key: key.to_sym)
    end

    # Inline SVG: a coloured disc with the glyph. Every part comes from the
    # fixed tables above (the key is looked up, never interpolated), so the
    # markup is safe by construction and is marked so here.
    def svg(key, size: 28)
      badge = LEVELS.fetch(key.to_sym)
      %(<svg class="badge-mark" width="#{size.to_i}" height="#{size.to_i}" viewBox="0 0 28 28" role="img" aria-label="#{badge[:label]}"><circle cx="14" cy="14" r="13" fill="#{badge[:color]}"/>#{GLYPHS.fetch(badge[:glyph])}</svg>).html_safe # rubocop:disable Rails/OutputSafety
    end

    STROKE = 'fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"'
    GLYPHS = {
      double_check: %(<path d="M6 14.5l4 4 5-7" #{STROKE}/><path d="M13 18.5l2 2 6-8" #{STROKE}/>),
      check: %(<path d="M8 14.5l4 4 8-9" #{STROKE}/>),
      check_outline: %(<path d="M8 14.5l4 4 8-9" #{STROKE} stroke-dasharray="3 2"/>),
      tilde: %(<path d="M7 15c2-3 4-3 6 0s4 3 6 0" #{STROKE}/>),
      cross_outline: %(<path d="M9 9l10 10M19 9L9 19" #{STROKE} stroke-dasharray="3 2"/>),
      cross: %(<path d="M9 9l10 10M19 9L9 19" #{STROKE}/>),
      double_cross: %(<path d="M7 9l7 7M14 9l-7 7" #{STROKE}/><path d="M14 12l7 7M21 12l-7 7" #{STROKE}/>),
      question: %(<path d="M10.5 11a3.5 3.5 0 1 1 5 3.2c-1 .6-1.5 1.2-1.5 2.3" #{STROKE}/><circle cx="14" cy="20.5" r="1.4" fill="#fff"/>),
      quote: %(<path d="M9 17v-4a3 3 0 0 1 3-3M17 17v-4a3 3 0 0 1 3-3" #{STROKE}/>),
      lock: %(<rect x="8" y="13" width="12" height="9" rx="2" fill="#fff"/><path d="M10.5 13v-3a3.5 3.5 0 0 1 7 0v3" #{STROKE}/>)
    }.freeze
  end
end
