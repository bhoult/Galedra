# frozen_string_literal: true

module Scoring
  # Sensitivity to model variants (spec 03 §9).
  module Stability
    module_function

    # Returns [stability, variants_hash]; variants carry the fixed-place strings.
    def evaluate(config, prior_log_odds, evidence_sum, probability, groups, claim_type)
      st = config.fetch("stability")
      places = config.dig("rounding", "probability") || 4
      variants = st.fetch("variants").to_h do |name, factor|
        [ name, Decimal.round(Decimal.sigmoid(prior_log_odds + evidence_sum * Decimal.d(factor)), places) ]
      end
      all = [ probability ] + variants.values
      spread = all.max - all.min
      stability = if spread <= Decimal.d(st.fetch("spread_high_max")) then "HIGH"
      elsif spread <= Decimal.d(st.fetch("spread_medium_max")) then "MEDIUM"
      else "LOW"
      end
      stability = "MEDIUM" if stability == "HIGH" && groups < st.fetch("min_groups_for_high")
      stability = st.fetch("model_dependent_cap") if config.fetch("model_dependent_types").include?(claim_type)
      trace = variants.transform_values { |v| Decimal.fixed(v, places) }.merge("spread" => Decimal.fixed(spread, places))
      [ stability, trace, variants.values ]
    end
  end
end
