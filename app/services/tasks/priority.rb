# frozen_string_literal: true

module Tasks
  # Task board priority (spec 03 §14): a labelled heuristic, never a score input.
  module Priority
    module_function

    def call(probability:, downstream_count:, review_coverage:, task_type:, config:)
      p = probability.nil? ? nil : Scoring::Decimal.d(probability)
      uncertainty = p.nil? ? BigDecimal(1) : BigDecimal(1) - (BigDecimal(2) * p - BigDecimal(1)).abs
      impact = BigDecimal(1) + Scoring::Decimal.ln(BigDecimal(1) + BigDecimal(downstream_count))
      coverage_gap = BigDecimal(1) - Scoring::Decimal.d(review_coverage)
      cost = Scoring::Decimal.d(config.fetch("task_type_cost").fetch(task_type))
      Scoring::Decimal.fixed((uncertainty * impact * (BigDecimal("0.5") + coverage_gap)).div(cost, Scoring::Decimal::PRECISION), 4)
    end
  end
end
