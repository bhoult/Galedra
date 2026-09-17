# frozen_string_literal: true

module Scoring
  # Two models over the same evidence (spec 03 §13, constitution Art. XVI):
  # which links weigh differently, which config keys are responsible, and any
  # change of state.
  module Compare
    module_function

    def call(result_a, result_b, config_a:, config_b:)
      diff = config_diff(config_a, config_b)
      links_a = result_a.trace["links"].index_by { |l| l["link"] }
      links_b = result_b.trace["links"].index_by { |l| l["link"] }
      link_diffs = (links_a.keys | links_b.keys).filter_map do |id|
        a = links_a[id]
        b = links_b[id]
        next if a && b && a["effective_weight"] == b["effective_weight"] && a["magnitude"] == b["magnitude"]

        { "link" => id, "effective_weight" => { result_a.trace["model"] => a&.dig("effective_weight"), result_b.trace["model"] => b&.dig("effective_weight") },
          "responsible" => responsible_for(a || b, diff) }
      end
      state_change = result_a.assessment_state == result_b.assessment_state ? nil : { "from" => result_a.assessment_state, "to" => result_b.assessment_state }
      state_keys = if state_change
        applicability = [ result_a, result_b ].map(&:assessment_state).include?("NOT_APPLICABLE") && diff.any? { |k| k.start_with?("scored_types") }
        applicability ? [ "scored_types" ] + link_diffs.flat_map { |l| l["responsible"] }.uniq : link_diffs.flat_map { |l| l["responsible"] }.uniq
      else
        []
      end
      {
        "models" => [ result_a.trace["model"], result_b.trace["model"] ],
        "assessment" => { result_a.trace["model"] => result_a.to_h_public.deep_stringify_keys, result_b.trace["model"] => result_b.to_h_public.deep_stringify_keys },
        "config_diff" => diff, "links" => link_diffs,
        "state_change" => state_change, "responsible_config_keys" => state_keys.uniq
      }
    end

    # Dotted paths whose values differ; array-valued keys diff as a whole.
    def config_diff(a, b, prefix = nil)
      (a.keys | b.keys).flat_map do |key|
        path = [ prefix, key ].compact.join(".")
        va = a[key]
        vb = b[key]
        if va.is_a?(Hash) && vb.is_a?(Hash)
          config_diff(va, vb, path)
        elsif va != vb
          [ path ]
        else
          []
        end
      end.sort
    end

    def responsible_for(link, diff)
      candidates = [
        "relevance_weight.#{link['relevance']}", "observation_weight.#{link['observation']}",
        "authenticity_factor.#{link['authenticity']}", "extraction_factor.#{link['extraction']}",
        "interpretive_step_penalty", "direction_sign.#{link['direction']}", "scored_types", "independence_strategy"
      ]
      diff & candidates
    end
  end
end
