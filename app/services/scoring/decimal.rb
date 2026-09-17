# frozen_string_literal: true

require "bigdecimal"
require "bigdecimal/math"

module Scoring
  # Exact arithmetic for the scorer (spec 03 §4, §10): BigDecimal throughout,
  # round half to even, decimals serialized as fixed-place strings, and
  # transcendental functions evaluated at high precision then rounded.
  module Decimal
    PRECISION = 40
    ROUNDING = BigDecimal::ROUND_HALF_EVEN

    module_function

    def d(value)
      value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
    end

    def round(value, places)
      d(value).round(places, ROUNDING)
    end

    def fixed(value, places)
      text = round(value, places).to_s("F")
      whole, frac = text.split(".")
      frac = (frac || "").ljust(places, "0")
      places.zero? ? whole : "#{whole}.#{frac}"
    end

    def ln(value)
      BigMath.log(d(value), PRECISION)
    end

    def exp(value)
      BigMath.exp(d(value), PRECISION)
    end

    def sigmoid(value)
      BigDecimal(1).div(BigDecimal(1) + exp(-d(value)), PRECISION)
    end

    def log_odds(probability)
      p = d(probability)
      ln(p.div(BigDecimal(1) - p, PRECISION))
    end

    # True when rounding `value` to `places` sits within `guard` of a boundary,
    # so another implementation's transcendental math could round differently.
    def near_boundary?(value, places, guard)
      scaled = d(value) * (BigDecimal(10)**places)
      frac = scaled - scaled.floor
      (frac - BigDecimal("0.5")).abs < d(guard) * (BigDecimal(10)**places)
    end
  end
end
