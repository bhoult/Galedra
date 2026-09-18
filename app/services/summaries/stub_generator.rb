# frozen_string_literal: true

module Summaries
  # stub-v0.1 (spec 04 §10): sentences filled from the trace, each citing the
  # graph ids it restates. Deterministic.
  module StubGenerator
    NAME = "stub-v0.1"

    module_function

    def sentences(input, type:)
      all = build(input)
      all.first(Validator::MAX.fetch(type))
    end

    def build(input)
      out = []
      state = input["assessment_state"]
      headline = Cards::Headline.for(state)
      kept = input["kept"]
      supports = kept.select { |k| k["direction"] == "SUPPORT" }
      contradictions = kept.select { |k| k["direction"] == "CONTRADICT" }
      claim_id = input.dig("claim", "id")

      if state == "NOT_APPLICABLE"
        out << { "text" => "#{headline}. #{Cards::Headline.reason_text(input['not_applicable_reason'])}", "cites" => [ "coverage:#{claim_id}" ] }
      elsif state == "INSUFFICIENT_EVIDENCE"
        out << { "text" => "#{headline}. No counted evidence bears on this claim yet.", "cites" => [ "coverage:#{claim_id}" ] }
      else
        lead = supports.first || contradictions.first
        out << { "text" => "#{headline}. #{lead['direction'] == 'SUPPORT' ? 'The main support is' : 'The main contradiction is'}: #{lead['statement']}", "cites" => [ lead["evidence"] ] } if lead
        other = lead && lead["direction"] == "SUPPORT" ? contradictions.first : supports.first
        out << { "text" => "#{other['direction'] == 'SUPPORT' ? 'Against that, support' : 'Against that, contradiction'}: #{other['statement']}", "cites" => [ other["evidence"] ] } if other
      end

      suppressed = input["suppressed"]
      if suppressed.any?
        groups = suppressed.map { |s| s["group"] }.compact.uniq
        out << { "text" => "#{suppressed.size} further item#{'s' if suppressed.size != 1} repeat#{'s' if suppressed.size == 1} the same origin and #{suppressed.size == 1 ? 'is' : 'are'} not independent evidence.", "cites" => groups.presence || suppressed.map { |s| s["evidence"] } }
      end
      input["qualifiers"].each do |q|
        out << { "text" => "Qualifier: #{q['statement']}", "cites" => [ q["evidence"] ] }
      end
      input["related"].select { |r| r["relation"] == "NARROWS" && r["direction"] == "incoming" }.each do |r|
        out << { "text" => "A narrower version of this claim is #{Cards::Headline.for(r['assessment_state']).downcase}.", "cites" => [ r["claim_id"] ] }
      end
      input["audits"].select { |a| %w[SUBSTANTIVE_ERROR FABRICATION].include?(a["result"]) && !a["overturned"] }.each do |a|
        out << { "text" => "An earlier verification was rejected on audit.", "cites" => [ "audit:#{a['audit']}" ] }
      end
      input.fetch("task_results", []).select { |t| t["task_type"] == "OPPOSING_EVIDENCE_SEARCH" }.each do |t|
        text = t["outcome"] == "NONE_FOUND" ? "A search for evidence in the opposing direction found none." : "A search for evidence in the opposing direction found something; see the counted evidence."
        out << { "text" => text, "cites" => [ t["task_id"] ] }
      end
      checks = input["review_checklist"]
      out << { "text" => "Review checks: #{checks.count { |_, v| v['ok'] }} of #{checks.size}.", "cites" => [ "coverage:#{claim_id}" ] }
      out
    end
  end
end
