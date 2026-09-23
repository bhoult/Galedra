# frozen_string_literal: true

module Cards
  # "Show me why" (spec 01 §6): the strongest counted support and contradiction,
  # suppressed dependents, review gaps, and the single evidence addition that
  # would move the score most under this model, found by re-running the scorer
  # with one hypothetical independent link.
  module Why
    HYPOTHETICALS = [
      { "direction" => "SUPPORT", "relevance_strength" => "DIRECT", "observation_type" => "MEASUREMENT" },
      { "direction" => "CONTRADICT", "relevance_strength" => "DIRECT", "observation_type" => "MEASUREMENT" }
    ].freeze

    module_function

    def call(claim, seq, model)
      result = Scoring::Score.call(claim, seq, model)
      links = result.trace["links"]
      statements = EvidenceItem.where(id: links.map { |l| l["evidence"] }).pluck(:id, :statement).to_h
      counted = links.select { |l| l["effective_weight"] && BigDecimal(l["effective_weight"]).positive? }
      strongest = ->(dir) { counted.select { |l| l["direction"] == dir }.max_by { |l| BigDecimal(l["effective_weight"]) } }
      {
        claim_id: claim.id, snapshot_seq: seq, model: model.full_name, assessment_state: result.assessment_state,
        strongest_support: describe(strongest.call("SUPPORT"), statements),
        strongest_contradiction: describe(strongest.call("CONTRADICT"), statements),
        suppressed_dependents: links.select { |l| l["reason"] == "dependent_strongest_only" }.map { |l| { link: l["link"], evidence: l["evidence"], group: l["group"], kept: l["kept"], statement: statements[l["evidence"]] } },
        review_gaps: result.review_checklist.reject { |_, v| v["ok"] }.keys,
        what_would_most_change_this: most_moving_addition(claim, seq, model, result)
      }
    end

    def describe(link, statements)
      return nil if link.nil?

      { link: link["link"], evidence: link["evidence"], effective_weight: link["effective_weight"], relevance: link["relevance"],
        observation: link["observation"], statement: statements[link["evidence"]] }
    end

    # `input` may be passed in by a caller that built a set of them at once
    # (Scoring::BuildInput.call_many); it is the same input either way.
    def most_moving_addition(claim, seq, model, result, input: nil)
      return nil if result.assessment_state == "NOT_APPLICABLE"

      input ||= Scoring::BuildInput.call(claim, seq)
      base = result.probability && BigDecimal(result.probability)
      candidates = HYPOTHETICALS.map do |h|
        hypothetical = { "id" => "hypothetical", "evidence_id" => "hypothetical", "direction" => h["direction"], "relevance_strength" => h["relevance_strength"],
                         "interpretive_steps" => 0, "audit_confirmed" => true,
                         "evidence" => { "observation_type" => h["observation_type"], "independence_group_id" => nil, "source_type" => "MEASUREMENT", "assessment" => {} } }
        moved = Scoring::Calculate.call(input.merge("links" => input["links"] + [ hypothetical ]), config: model.config, model: model.full_name, code_hash: model.code_hash)
        to = moved.probability && BigDecimal(moved.probability)
        delta = base && to ? (to - base).abs : (to || BigDecimal(0))
        { direction: h["direction"], relevance: h["relevance_strength"], observation: h["observation_type"], independent: true,
          probability_from: result.probability, probability_to: moved.probability, state_from: result.assessment_state, state_to: moved.assessment_state, delta: delta }
      end
      best = candidates.max_by { |c| [ c[:delta], c[:direction] == "CONTRADICT" ? 1 : 0 ] }
      best.merge(delta: Scoring::Decimal.fixed(best[:delta], 4),
                 text: "One independent, direct #{best[:observation].downcase} that #{best[:direction] == 'SUPPORT' ? 'supports' : 'contradicts'} this claim would move it from #{Headline.for(best[:state_from])} to #{Headline.for(best[:state_to])}.")
    end
  end
end
