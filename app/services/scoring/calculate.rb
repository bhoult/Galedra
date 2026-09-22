# frozen_string_literal: true

module Scoring
  # The v0.1 algorithm (spec 03 §4), implemented exactly and as a pure function
  # of a serializable input (11 §12) and a model config. Same input, same
  # config, same code: byte-identical trace.
  #
  # input = {
  #   "claim" => {"id", "type", "truth_evaluable", "not_evaluable_reason"},
  #   "snapshot_seq" => Integer,
  #   "links" => [{"id", "evidence_id", "direction", "relevance_strength", "interpretive_steps",
  #                "audit_confirmed", "evidence" => {"observation_type", "independence_group_id",
  #                "source_type", "assessment" => {"authenticity", "extraction"}}}],
  #   "task_checks" => [{"check", "by"}]
  # }
  class Calculate
    # `unchanged_since` (Stage 38) is not part of the assessment and never
    # reaches a trace: it is the seq this score was computed at, set when the
    # answer is served for a later seq at which nothing bearing on it had moved.
    Result = Struct.new(:assessment_state, :probability, :review_coverage, :review_checklist, :stability,
                        :support_groups, :contradict_groups, :independence_unreviewed, :contested, :provisional,
                        :not_applicable_reason, :model_dependent, :trace, :trace_hash, :unchanged_since,
                        keyword_init: true) do
      def to_h_public
        to_h.except(:trace, :trace_hash, :unchanged_since)
      end
    end

    NON_DIRECTIONAL = "non_directional"
    DEPENDENT = "dependent_strongest_only"
    # A reading of a different version of the document the claim names
    # (0.3.0). Recorded as a reason rather than a silent zero, because a reader
    # looking at a contradiction that does not count is owed the word "why".
    OTHER_EDITION = "other_edition"

    def self.call(input, config:, model:, code_hash: Registry.code_hash)
      new(input, config, model, code_hash).call
    end

    def initialize(input, config, model, code_hash)
      @input = input.deep_stringify_keys
      @config = config
      @model = model
      @code_hash = code_hash
      @claim = @input.fetch("claim")
      @links = @input.fetch("links", []).sort_by { |l| l["id"].to_s }
      @places = { weights: @config.dig("rounding", "weights") || 6, probability: @config.dig("rounding", "probability") || 4 }
      @guard = Decimal.d(@config.dig("rounding", "boundary_guard") || "1e-6")
    end

    def call
      checklist, coverage = Checklist.evaluate(@config, @links, @input.fetch("task_checks", []))
      unreviewed = @links.reject { |l| l.dig("evidence", "independence_group_id").present? }.map { |l| l["evidence_id"] }.uniq.size
      provisional = @links.any? { |l| l["audit_confirmed"] == false }
      model_dependent = @config.fetch("model_dependent_types").include?(@claim["type"])
      weighted = weigh_links

      # Step 0 — applicability
      unless applicable?
        reason = @claim["truth_evaluable"] ? "NOT_SCORED_BY_MODEL" : @claim["not_evaluable_reason"]
        return finish(state: "NOT_APPLICABLE", probability: nil, stability: nil, reason: reason, checklist: checklist,
                      coverage: coverage, unreviewed: unreviewed, provisional: provisional, model_dependent: model_dependent,
                      links: weighted.map { |w| link_trace(w, effective: nil, reason: "not_applicable") },
                      support: 0, contradict: 0, contested: false, sums: nil, variants: nil, boundary: false)
      end

      # Step 3 — strongest-only per (group, sign)
      kept = select_strongest(weighted)
      kept_ids = kept.values.map { |w| w[:link]["id"] }
      links_trace = weighted.map do |w|
        # Direction first. A QUALIFY or NEUTRAL link weighs nothing because of
        # its direction, whatever edition it came from, and `non_directional` is
        # the reason two readers downstream match on — `Summaries::Input` picks
        # the summary's qualifier list by it, and `Cards::Why` its suppressed
        # list. Stamping such a link `other_edition` dropped a material
        # qualifier out of the summary entirely, with nothing in its place
        # (code review, 2026-09-22).
        if w[:sign].zero?
          link_trace(w, effective: BigDecimal(0), reason: NON_DIRECTIONAL)
        elsif w[:other_edition]
          link_trace(w, effective: BigDecimal(0), reason: OTHER_EDITION)
        elsif kept_ids.include?(w[:link]["id"])
          link_trace(w, effective: w[:magnitude], reason: nil)
        else
          keeper = kept.fetch([ w[:group], w[:sign] ])
          link_trace(w, effective: BigDecimal(0), reason: DEPENDENT, kept: keeper[:link]["id"])
        end
      end
      support = kept.count { |(_, sign), w| sign.positive? && w[:magnitude].positive? }
      contradict = kept.count { |(_, sign), w| sign.negative? && w[:magnitude].positive? }

      if kept.empty? || kept.values.all? { |w| w[:magnitude].zero? }
        return finish(state: "INSUFFICIENT_EVIDENCE", probability: nil, stability: nil, reason: nil, checklist: checklist,
                      coverage: coverage, unreviewed: unreviewed, provisional: provisional, model_dependent: model_dependent,
                      links: links_trace, support: 0, contradict: 0, contested: false, sums: nil, variants: nil, boundary: false)
      end

      # Step 4 — combine
      p0 = Decimal.d(@config.fetch("prior").fetch(@claim["type"]))
      raw_prior = Decimal.log_odds(p0)
      prior_log_odds = Decimal.round(raw_prior, @places[:weights])
      evidence_sum = Decimal.round(kept.values.sort_by { |w| w[:link]["id"].to_s }.sum(BigDecimal(0)) { |w| w[:magnitude] * w[:sign] }, @places[:weights])
      posterior = prior_log_odds + evidence_sum
      raw_probability = Decimal.sigmoid(posterior)
      probability = Decimal.round(raw_probability, @places[:probability])

      # Step 5 — state (directional states require matching evidence)
      t = @config.fetch("state_thresholds")
      state = if probability >= Decimal.d(t["SUPPORTED"]) && support.positive? then "SUPPORTED"
      elsif probability >= Decimal.d(t["LEANS_SUPPORTED"]) && support.positive? then "LEANS_SUPPORTED"
      elsif probability <= Decimal.d(t["LEANS_CONTRADICTED_ABOVE"]) && contradict.positive? then "CONTRADICTED"
      elsif probability <= Decimal.d(t["UNRESOLVED_ABOVE"]) && contradict.positive? then "LEANS_CONTRADICTED"
      else "UNRESOLVED"
      end

      stability, variants_trace, variant_values = Stability.evaluate(@config, prior_log_odds, evidence_sum, probability, support + contradict, @claim["type"])
      # The guard is absolute (03 §10: within 1e-6 of a boundary), so it is
      # applied to the 4-place probabilities, where another implementation's
      # exp() could land on the other side; the 6-place prior is a per-type
      # constant every implementation can pin.
      boundary = Decimal.near_boundary?(raw_probability, @places[:probability], @guard) ||
                 @config.fetch("stability").fetch("variants").values.any? { |f| Decimal.near_boundary?(Decimal.sigmoid(prior_log_odds + evidence_sum * Decimal.d(f)), @places[:probability], @guard) }

      finish(state: state, probability: probability, stability: stability, reason: nil, checklist: checklist, coverage: coverage,
             unreviewed: unreviewed, provisional: provisional, model_dependent: model_dependent, links: links_trace,
             support: support, contradict: contradict, contested: support.positive? && contradict.positive?,
             sums: { prior: p0, prior_log_odds: prior_log_odds, evidence_sum: evidence_sum, posterior: posterior },
             variants: variants_trace, boundary: boundary)
    end

    private

    def applicable?
      @claim["truth_evaluable"] == true && @config.fetch("scored_types").include?(@claim["type"])
    end

    # Step 2 — weight each link
    def weigh_links
      @links.map do |link|
        evidence = link.fetch("evidence")
        assessment = evidence.fetch("assessment", {})
        relevance = Decimal.d(@config.fetch("relevance_weight").fetch(link.fetch("relevance_strength")))
        observation = Decimal.d(@config.fetch("observation_weight").fetch(evidence.fetch("observation_type")))
        penalty = Decimal.d(@config.fetch("interpretive_step_penalty"))
        interpretation = [ BigDecimal(0), BigDecimal(1) - penalty * link.fetch("interpretive_steps", 0) ].max
        authenticity = Decimal.d(@config.fetch("authenticity_factor").fetch(assessment.fetch("authenticity", "UNVERIFIED")))
        extraction = Decimal.d(@config.fetch("extraction_factor").fetch(assessment.fetch("extraction", "UNVERIFIED")))
        # Stage 35. Evidence drawn from an origin the claim was extracted from
        # shows the quotation is faithful; it says nothing about whether the
        # speaker was right. Both this and the origin grouping below are read
        # from the config, so a model that declares neither scores exactly as it
        # always did and every trace it produced stays reproducible.
        provenance = provenance_factor(link)
        magnitude = Decimal.round(relevance * observation * interpretation * authenticity * extraction * provenance, @places[:weights])
        sign = @config.fetch("direction_sign").fetch(link.fetch("direction"))
        group = evidence["independence_group_id"].presence || fallback_group(link, evidence)
        # 0.3.0. A reading of a different version of the document the claim
        # names is a reading of a different text, so it weighs nothing here. It
        # is still recorded, still shown, and still says why in the trace — the
        # link is not deleted and nobody's work is discarded, it simply stops
        # being evidence about this claim. A model without the key never asks.
        other = other_edition?(link)
        { link: link, magnitude: other ? BigDecimal(0) : magnitude, sign: sign, group: group, other_edition: other }
      end
    end

    # Step 3 — within each (group, sign) keep the largest magnitude; ties go
    # to the lowest evidence id, then the lowest link id (03 §4). "Lowest id"
    # assumes time-ordered ids; projection ids here are hash-derived, so the
    # rows' created_seq (when the input carries it) is compared first, which is
    # the order UUIDv7 ids would have given and the reference's handles encode.
    def select_strongest(weighted)
      kept = {}
      weighted.each do |w|
        next if w[:sign].zero?

        key = [ w[:group], w[:sign] ]
        current = kept[key]
        better = current.nil? || w[:magnitude] > current[:magnitude] ||
                 (w[:magnitude] == current[:magnitude] && (tie_key(w[:link]) <=> tie_key(current[:link])).negative?)
        kept[key] = w if better
      end
      kept
    end

    def tie_key(link)
      [ link.dig("evidence", "created_seq") || 0, link["evidence_id"].to_s, link["created_seq"] || 0, link["id"].to_s ]
    end

    # Declared by the model, like every other rule that changes a number: a
    # config without `edition_rule` scores exactly as it did, so 0.1.0 and
    # 0.2.0 stay reproducible byte for byte.
    def other_edition?(link)
      return false unless @config["edition_rule"] == "named_edition_only"

      link["different_edition"] == true
    end

    def provenance_factor(link)
      factors = @config["provenance_factor"]
      return BigDecimal(1) if factors.nil?

      Decimal.d(factors.fetch(link["self_referential"] ? "SELF" : "INDEPENDENT"))
    end

    # Ungrouped evidence is its own group. Under "origin" it is keyed by where it
    # came from *and which passage it is*, so the same passage recorded twice —
    # which happens whenever one URL is entered as two sources, and nothing
    # deduplicates by address — counts once. Two different passages of one
    # document stay distinct: a qualifier and a supporting line from the same
    # report are not each other repeated, and collapsing them would throw away
    # the qualifier, which is information rather than duplication.
    def fallback_group(link, evidence)
      return "solo:#{link.fetch('evidence_id')}" unless @config["independence_fallback"] == "origin"
      return "solo:#{link.fetch('evidence_id')}" if evidence["origin"].blank?

      "origin:#{evidence['origin']}/#{evidence['passage']}"
    end

    def link_trace(w, effective:, reason:, kept: nil)
      link = w[:link]
      evidence = link.fetch("evidence")
      entry = {
        "link" => link["id"], "evidence" => link["evidence_id"], "direction" => link["direction"],
        "group" => evidence["independence_group_id"], "relevance" => link["relevance_strength"],
        "observation" => evidence["observation_type"], "interpretive_steps" => link.fetch("interpretive_steps", 0),
        "authenticity" => evidence.fetch("assessment", {}).fetch("authenticity", "UNVERIFIED"),
        "extraction" => evidence.fetch("assessment", {}).fetch("extraction", "UNVERIFIED"),
        "source_type" => evidence["source_type"], "audit_confirmed" => link["audit_confirmed"] != false,
        "magnitude" => Decimal.fixed(w[:magnitude], @places[:weights]),
        **(@config["provenance_factor"] ? { "provenance" => link["self_referential"] ? "SELF" : "INDEPENDENT" } : {}),
        **(@config["edition_rule"] ? { "edition" => link["different_edition"] ? "OTHER" : "NAMED_OR_UNRELATED" } : {}),
        "effective_weight" => effective.nil? ? nil : Decimal.fixed(effective, @places[:weights])
      }
      entry["reason"] = reason if reason
      entry["kept"] = kept if kept
      entry
    end

    def finish(state:, probability:, stability:, reason:, checklist:, coverage:, unreviewed:, provisional:, model_dependent:,
               links:, support:, contradict:, contested:, sums:, variants:, boundary:)
      pp = @places[:probability]
      wp = @places[:weights]
      trace = {
        "claim" => @claim["id"], "snapshot_seq" => @input["snapshot_seq"], "model" => @model,
        "config_hash" => Crypto::Hashing.json(@config), "code_hash" => @code_hash,
        "claim_type" => @claim["type"], "truth_evaluable" => @claim["truth_evaluable"],
        "prior" => sums && Decimal.fixed(sums[:prior], 2),
        "prior_log_odds" => sums && Decimal.fixed(sums[:prior_log_odds], wp),
        "links" => links,
        "evidence_sum" => sums && Decimal.fixed(sums[:evidence_sum], wp),
        "posterior_log_odds" => sums && Decimal.fixed(sums[:posterior], wp),
        "probability" => probability && Decimal.fixed(probability, pp),
        "rounding_boundary" => boundary,
        "variants" => variants, "stability" => stability, "assessment_state" => state,
        "support_groups" => support, "contradict_groups" => contradict, "independence_unreviewed" => unreviewed,
        "contested" => contested, "provisional" => provisional, "model_dependent" => model_dependent,
        "not_applicable_reason" => reason, "review_checklist" => checklist, "review_coverage" => Decimal.fixed(coverage, 2)
      }
      Result.new(
        assessment_state: state, probability: probability && Decimal.fixed(probability, pp), review_coverage: Decimal.fixed(coverage, 2),
        review_checklist: checklist, stability: stability, support_groups: support, contradict_groups: contradict,
        independence_unreviewed: unreviewed, contested: contested, provisional: provisional, not_applicable_reason: reason,
        model_dependent: model_dependent, trace: trace, trace_hash: Trace.hash(trace)
      )
    end
  end
end
