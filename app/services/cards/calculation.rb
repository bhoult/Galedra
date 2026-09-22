# frozen_string_literal: true

module Cards
  # The arithmetic behind a number, in the form a reader can check with a
  # calculator (owner, 2026-09-22).
  #
  # "Show calculation" showed the result and the trace hash — the inputs and the
  # answer, with the working left out. Everything needed was already in the
  # trace and in the model's config; nothing here computes a score, and nothing
  # here may. It reads what the scorer recorded and lays it out.
  #
  # Two halves, because the algorithm has two (03 §4):
  #
  #   each link   relevance × observation × interpretation × authenticity
  #               × extraction × provenance  =  magnitude
  #   the claim   prior log-odds + the strongest magnitude per group and
  #               direction  =  posterior log-odds  →  probability
  #
  # A factor absent from the model's config is absent here too, rather than
  # shown as 1: a model that does not weigh provenance should not appear to.
  module Calculation
    Factor = Struct.new(:name, :label, :value, keyword_init: true)

    module_function

    def call(trace, config)
      return nil if trace.blank? || config.blank?

      { links: Array(trace["links"]).map { |link| row(link, config) },
        prior: trace["prior"], prior_log_odds: trace["prior_log_odds"],
        evidence_sum: trace["evidence_sum"], posterior_log_odds: trace["posterior_log_odds"],
        probability: trace["probability"], variants: trace["variants"],
        boundary: trace["rounding_boundary"] }
    end

    # One link's factors, in the order the algorithm multiplies them.
    def row(link, config)
      factors = [
        factor("relevance", link["relevance"], config.dig("relevance_weight", link["relevance"])),
        factor("observation", link["observation"], config.dig("observation_weight", link["observation"])),
        steps_factor(link, config),
        factor("authenticity", link["authenticity"], config.dig("authenticity_factor", link["authenticity"])),
        factor("extraction", link["extraction"], config.dig("extraction_factor", link["extraction"]))
      ]
      factors << factor("provenance", link["provenance"], config.dig("provenance_factor", link["provenance"])) if link.key?("provenance")
      factors << factor("edition", link["edition"], link["edition"] == "OTHER" ? "0" : "1") if link.key?("edition")

      { link: link, factors: factors.compact, magnitude: link["magnitude"],
        effective_weight: link["effective_weight"], reason: link["reason"], kept: link["kept"] }
    end

    # 1 − penalty × steps, floored at zero (03 §4 Step 2). Written out rather
    # than reduced to its result, because the penalty is the part a reader is
    # most likely to want to check.
    def steps_factor(link, config)
      penalty = config["interpretive_step_penalty"]
      steps = link["interpretive_steps"].to_i
      return nil if penalty.blank?

      value = [ 0, 1 - (BigDecimal(penalty.to_s) * steps) ].max
      Factor.new(name: "interpretation", label: "#{steps} #{'step'.pluralize(steps)}, 1 − #{penalty} × #{steps}",
                 value: Scoring::Decimal.fixed(value, 6))
    end

    def factor(name, label, value)
      return nil if value.nil?

      Factor.new(name: name, label: label, value: value.to_s)
    end

    # The multiplication, as text, so it can be read straight off the page.
    def sentence(row)
      "#{row[:factors].map(&:value).join(' × ')} = #{row[:magnitude]}"
    end
  end
end
