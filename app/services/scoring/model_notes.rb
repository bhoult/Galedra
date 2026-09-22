# frozen_string_literal: true

module Scoring
  # What each released model is, and how it differs from the ones before it.
  #
  # Two halves, deliberately. **What differs is computed** by comparing the
  # configs, so it can never drift from what the models actually say — the
  # failure this project keeps hitting is a second copy of a fact going stale,
  # and a hand-written list of differences is exactly that. **What a model is
  # for** is prose, because intent is not derivable: nothing in a config says
  # why the strict model refuses to score a causal claim.
  #
  # Nothing here is written into a config. A released config's hash is recorded
  # in every trace it produced, so adding so much as a description to one would
  # break the reproducibility of every score already served (Invariant 4).
  module ModelNotes
    PURPOSE = {
      "ledger-default" => "The everyday model. It scores every claim type that can be scored at all, " \
                          "including causal and interpretive claims, and marks those two as model-dependent " \
                          "so a reader knows another model may disagree.",
      "ledger-strict" => "The cautious counterpart. It refuses to score the claim types where reasonable " \
                         "models differ most — causal and interpretive — rather than produce a number it " \
                         "would have to hedge. Where the two models disagree about a claim, that " \
                         "disagreement is itself reported, on the weaknesses page."
    }.freeze

    # What a version introduced. Prose, for the same reason as PURPOSE: the
    # config says a key appeared, not why anyone wanted it.
    VERSIONS = {
      "0.1.0" => "The algorithm as first specified: relevance, observation, interpretation, authenticity " \
                 "and extraction, strongest-only within each independence group, log-odds combination.",
      "0.2.0" => "Evidence from a source the claim was taken out of stops counting as support for it — " \
                 "that is provenance, not corroboration. Ungrouped evidence is keyed by origin and " \
                 "passage, so one page recorded twice as two sources counts once.",
      "0.3.0" => "A claim may name the edition of a source it is about. A reading of a different version " \
                 "of that source no longer counts against it, which matters for any claim about what a " \
                 "living web page said on a particular day."
    }.freeze

    # Keys whose difference is worth showing as a difference rather than a wall
    # of numbers; the rest are summarised as "the weights differ".
    NAMED = {
      "scored_types" => "claim types it scores",
      "model_dependent_types" => "types it marks as model-dependent",
      "provenance_factor" => "evidence from the claim's own source",
      "independence_fallback" => "how ungrouped evidence is grouped",
      "edition_rule" => "editions of a source"
    }.freeze

    # One line for a list of models. Prose where we have it; derived from the
    # config where we do not, because at a hundred released models most will
    # never have had a sentence written about them and "no description" is worse
    # than a true one nobody wrote.
    SHORT = {
      "ledger-default" => "Scores every claim type that can be scored, and marks the ones where models reasonably differ.",
      "ledger-strict" => "Declines to score the types where models differ most, rather than hedge a number."
    }.freeze

    VERSION_SHORT = {
      "0.1.0" => "the algorithm as first specified",
      "0.2.0" => "a source cannot corroborate itself",
      "0.3.0" => "a claim may name the edition it is about"
    }.freeze

    module_function

    # [what it is, what its version changed] — both one line, both safe to show
    # a hundred times.
    def summary(model)
      [ SHORT[model.name] || derived(model), VERSION_SHORT[model.semantic_version] ]
    end

    def derived(model)
      scored = Array(model.config["scored_types"]).size
      declared = [ ("weighs a source's own evidence at nothing" if model.config["provenance_factor"]),
                   ("honours the edition a claim names" if model.config["edition_rule"]) ].compact
      [ "Scores #{scored} claim #{'type'.pluralize(scored)}", declared.to_sentence.presence ].compact.join("; ") + "."
    end

    def for(model, others)
      previous = others.select { |m| m.name == model.name && m.semantic_version < model.semantic_version }
                       .max_by(&:semantic_version)
      sibling = others.find { |m| m.name != model.name && m.semantic_version == model.semantic_version }
      { purpose: PURPOSE[model.name], version: VERSIONS[model.semantic_version],
        since: previous && differences(previous.config, model.config),
        from_sibling: sibling && { model: sibling, differences: differences(sibling.config, model.config) } }
    end

    # [[what, before, after]] for the settings that differ, named where a name
    # helps. Two weight tables that differ in one entry are reported as that one
    # entry: printing both tables whole is how a difference gets hidden inside
    # forty numbers that are the same.
    def differences(before, after)
      (before.keys | after.keys).sort.filter_map do |key|
        next if %w[name semantic_version].include?(key) || before[key] == after[key]

        what = NAMED[key] || key.tr("_", " ")
        if before[key].is_a?(Hash) && after[key].is_a?(Hash)
          inner_differences(what, before[key], after[key])
        else
          [ [ what, summarise(before[key]), summarise(after[key]) ] ]
        end
      end.flatten(1)
    end

    def inner_differences(what, before, after)
      (before.keys | after.keys).sort.filter_map do |key|
        next if before[key] == after[key]

        [ "#{what}: #{key.to_s.tr('_', ' ').downcase}", summarise(before[key]), summarise(after[key]) ]
      end
    end

    def summarise(value)
      case value
      when nil then "not declared"
      when Array then value.empty? ? "none" : value.map { |v| v.to_s.tr("_", " ").downcase }.join(", ")
      when Hash then value.map { |k, v| "#{k.to_s.tr('_', ' ').downcase} #{v}" }.join(", ")
      else value.to_s.tr("_", " ")
      end
    end
  end
end
