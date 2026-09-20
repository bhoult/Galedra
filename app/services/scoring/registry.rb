# frozen_string_literal: true

module Scoring
  # Released scoring models (spec 02 §3.5, 05 §14): config validation, the
  # code hash over the scorer source, and lookup of released models.
  module Registry
    CODE_GLOB = "app/services/scoring/**/*.rb"
    CONFIG_DIR = "config/scoring"
    P0_TASK_TYPES = %w[CLAIM_EXTRACTION EVIDENCE_VERIFICATION OPPOSING_EVIDENCE_SEARCH SOURCE_INDEPENDENCE_CHECK QUALIFIER_CHECK].freeze
    REQUIRED_KEYS = %w[name semantic_version claim_types scored_types model_dependent_types prior relevance_weight
                       observation_weight interpretive_step_penalty authenticity_factor extraction_factor direction_sign
                       independence_strategy state_thresholds stability review_checklist primary_source_types
                       task_type_cost rounding].freeze
    DECIMAL = /\A-?\d+(\.\d+)?([eE]-?\d+)?\z/

    class Invalid < StandardError; end
    class CodeHashMismatch < StandardError; end

    module_function

    def code_hash
      files = Dir.glob(Rails.root.join(CODE_GLOB)).sort
      Crypto::Hashing.bytes(files.map { |f| "#{Pathname(f).relative_path_from(Rails.root)}\n#{File.read(f)}" }.join("\n"))
    end

    def config_files
      Dir.glob(Rails.root.join(CONFIG_DIR, "*.json")).sort
    end

    def load_config(path)
      JSON.parse(File.read(path))
    end

    def model_name(config) = "#{config['name']}@#{config['semantic_version']}"

    # Exhaustive validation: a missing enum key is a release error, never a
    # runtime default (spec 03 §4 Step 2), and every declared review check must
    # be satisfiable by a P0 task type (03 §8).
    def validate!(config)
      raise Invalid, "config must be an object" unless config.is_a?(Hash)
      missing = REQUIRED_KEYS - config.keys
      raise Invalid, "missing keys: #{missing.join(', ')}" if missing.any?
      raise Invalid, "semantic_version must be MAJOR.MINOR.PATCH" unless config["semantic_version"].to_s.match?(/\A\d+\.\d+\.\d+\z/)

      exhaustive!(config, "claim_types", Claim::TYPES, list: true)
      subset!(config, "scored_types", Claim::TYPES)
      subset!(config, "model_dependent_types", config["scored_types"])
      table!(config, "prior", config["scored_types"])
      table!(config, "relevance_weight", EvidenceClaimLink::STRENGTHS)
      table!(config, "observation_weight", EvidenceItem::OBSERVATION_TYPES)
      table!(config, "authenticity_factor", EvidenceItem::AUTHENTICITY)
      table!(config, "extraction_factor", EvidenceItem::EXTRACTION)
      decimal!(config, "interpretive_step_penalty")
      signs = config["direction_sign"]
      raise Invalid, "direction_sign must cover #{EvidenceClaimLink::DIRECTIONS.join(', ')} with -1, 0, or 1" unless signs.is_a?(Hash) &&
        (EvidenceClaimLink::DIRECTIONS - signs.keys).empty? && signs.values.all? { |v| [ -1, 0, 1 ].include?(v) }
      table!(config, "state_thresholds", %w[SUPPORTED LEANS_SUPPORTED UNRESOLVED_ABOVE LEANS_CONTRADICTED_ABOVE])
      st = config["stability"]
      raise Invalid, "stability must declare variants, spread_high_max, spread_medium_max, min_groups_for_high, model_dependent_cap" unless st.is_a?(Hash) &&
        %w[variants spread_high_max spread_medium_max min_groups_for_high model_dependent_cap].all? { |k| st.key?(k) } &&
        st["variants"].is_a?(Hash) && st["variants"].values.all? { |v| DECIMAL.match?(v.to_s) } &&
        %w[HIGH MEDIUM LOW].include?(st["model_dependent_cap"]) && st["min_groups_for_high"].is_a?(Integer)
      checklist!(config)
      subset!(config, "primary_source_types", Source::TYPES)
      table!(config, "task_type_cost", P0_TASK_TYPES)
      rounding = config["rounding"]
      raise Invalid, "rounding must declare weights, probability, coverage, mode, boundary_guard" unless rounding.is_a?(Hash) &&
        %w[weights probability coverage].all? { |k| rounding[k].is_a?(Integer) } && rounding["mode"] == "half_even" && DECIMAL.match?(rounding["boundary_guard"].to_s)
      config
    end

    def exhaustive!(config, key, expected, list: false)
      value = config[key]
      ok = list ? value.is_a?(Array) && value.sort == expected.sort : false
      raise Invalid, "#{key} must list exactly: #{expected.join(', ')}" unless ok
    end

    def subset!(config, key, allowed)
      value = config[key]
      raise Invalid, "#{key} must be an array drawn from: #{allowed.join(', ')}" unless value.is_a?(Array) && (value - allowed).empty?
    end

    def table!(config, key, expected_keys)
      table = config[key]
      raise Invalid, "#{key} must be an object" unless table.is_a?(Hash)
      missing = expected_keys - table.keys
      raise Invalid, "#{key} is missing #{missing.join(', ')}" if missing.any?
      bad = table.reject { |_, v| DECIMAL.match?(v.to_s) }.keys
      raise Invalid, "#{key} has non-decimal values for #{bad.join(', ')}" if bad.any?
    end

    def decimal!(config, key)
      raise Invalid, "#{key} must be a decimal string" unless DECIMAL.match?(config[key].to_s)
    end

    def checklist!(config)
      checks = config["review_checklist"]
      raise Invalid, "review_checklist must be a non-empty array" unless checks.is_a?(Array) && checks.any?
      unknown = checks - Checklist::KNOWN
      raise Invalid, "review_checklist declares unknown checks: #{unknown.join(', ')}" if unknown.any?
      unsatisfiable = checks.select { |c| Checklist::TASK_CHECKS.key?(c) && !P0_TASK_TYPES.include?(Checklist::TASK_CHECKS[c]) }
      raise Invalid, "review_checklist declares checks no P0 task type can satisfy: #{unsatisfiable.join(', ')}" if unsatisfiable.any?
    end

    # The RELEASE_SCORING_MODEL payload for a config file (spec 05 §14).
    def release_payload(config, test_suite_result_hash: nil)
      validate!(config)
      {
        "name" => config["name"], "semantic_version" => config["semantic_version"], "config" => config,
        "config_hash" => Crypto::Hashing.json(config), "code_hash" => code_hash,
        "test_suite_result_hash" => test_suite_result_hash
      }.compact
    end

    def released
      ScoringModel.order(:released_seq)
    end

    def find(name)
      short, version = name.to_s.split("@", 2)
      model = version ? ScoringModel.find_by(name: short, semantic_version: version) : ScoringModel.where(name: short).order(:released_seq).last
      raise Invalid, "no released model #{name}" if model.nil?
      model
    end

    # Which model a visitor sees when they ask for none. Newest-released was the
    # rule, which meant releasing a model silently changed what the whole node
    # reported — a switch that should be deliberate and announced, not a side
    # effect of a rake task. LEDGER_DEFAULT_MODEL pins it; absent, the newest
    # still wins, so nothing changes for a node that never sets it.
    def default_model
      pinned = ENV["LEDGER_DEFAULT_MODEL"].presence
      if pinned
        found = ScoringModel.find_by(name: pinned.split("@").first, semantic_version: pinned.split("@").last)
        return found if found
      end
      ScoringModel.where(name: "ledger-default").order(:released_seq).last || released.first
    end

    # The default model as it stood at a seq, so log-derived decisions replay identically.
    def default_model_at(seq)
      scope = ScoringModel.where(released_seq: ..seq)
      scope.where(name: "ledger-default").order(:released_seq).last || scope.order(:released_seq).first
    end

    # Every released model must carry the hash of the code now running; scorer
    # changes require a new version (spec 05 §14).
    def verify_code_hash!
      current = code_hash
      stale = released.reject { |m| m.code_hash == current }
      return true if stale.empty?

      raise CodeHashMismatch, "scorer code changed since #{stale.map(&:full_name).join(', ')} were released; release a new version"
    end

    def score(input, model)
      model = find(model) unless model.is_a?(ScoringModel)
      Calculate.call(input, config: model.config, model: model.full_name, code_hash: model.code_hash)
    end
  end
end
