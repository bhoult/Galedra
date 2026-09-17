# frozen_string_literal: true

module Scoring
  # The review checklist (spec 03 §8): derived entirely from the log, so
  # coverage is deterministic and never estimated.
  module Checklist
    KNOWN = %w[primary_source_reviewed opposing_search_done independence_reviewed qualifiers_reviewed].freeze
    TASK_CHECKS = {
      "opposing_search_done" => "OPPOSING_EVIDENCE_SEARCH",
      "independence_reviewed" => "SOURCE_INDEPENDENCE_CHECK",
      "qualifiers_reviewed" => "QUALIFIER_CHECK"
    }.freeze

    module_function

    # links: counted link inputs; task_checks: [{check:, by:}] from accepted task results.
    def evaluate(config, links, task_checks)
      checks = task_checks.map { |c| c.is_a?(Hash) ? [ c["check"], c["by"] ] : [ c.to_s, nil ] }
      by_check = checks.group_by(&:first).transform_values { |v| v.map(&:last).compact }
      primary = links.select { |l| config.fetch("primary_source_types").include?(l.dig("evidence", "source_type")) }
      grouped = links.any? && links.all? { |l| l.dig("evidence", "independence_group_id").present? }

      items = {
        "primary_source_reviewed" => [ primary.any?, primary.map { |l| l["id"] } ],
        "opposing_search_done" => [ by_check.key?("opposing_search_done"), by_check.fetch("opposing_search_done", []) ],
        "independence_reviewed" => [ grouped || by_check.key?("independence_reviewed"),
                                     by_check.key?("independence_reviewed") ? by_check["independence_reviewed"] : (grouped ? links.map { |l| l["id"] } : []) ],
        "qualifiers_reviewed" => [ by_check.key?("qualifiers_reviewed"), by_check.fetch("qualifiers_reviewed", []) ]
      }
      declared = config.fetch("review_checklist")
      checklist = declared.to_h { |name| [ name, { "ok" => items.fetch(name).first, "by" => items.fetch(name).last } ] }
      satisfied = checklist.count { |_, v| v["ok"] }
      coverage = Decimal.round(BigDecimal(satisfied).div(BigDecimal(declared.size), Decimal::PRECISION), config.dig("rounding", "coverage") || 2)
      [ checklist, coverage ]
    end
  end
end
