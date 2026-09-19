# frozen_string_literal: true

module Affiliations
  # Deduplicates a requested affiliation against what exists (owner request,
  # 2026-09-19): "dem" is Democrat, "ar" may be Arkansas once someone added it.
  # This is the stub behind Llm::Adapter#resolve_affiliation, and the shape a
  # real adapter must return: {slug:, confidence:} with confidence EXACT
  # (the slug or label itself), ALIAS (config/affiliation_aliases.yml),
  # SIMILAR (pg_trgm similarity at or above THRESHOLD, a proposal for an
  # admin), or NONE. Only EXACT and ALIAS are applied without a person.
  module Resolve
    ALIASES = Rails.root.join("config/affiliation_aliases.yml")
    THRESHOLD = 0.45

    module_function

    def normalize(text)
      text.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
    end

    def aliases
      @aliases ||= YAML.safe_load(File.read(ALIASES)).fetch("aliases").transform_keys { |k| normalize(k) }
    end

    def call(text)
      n = normalize(text)
      return { slug: nil, confidence: "NONE" } if n.empty?

      options = Affiliations.index.values
      if (hit = options.find { |o| normalize(o.slug) == n || normalize(o.label) == n })
        return { slug: hit.slug, confidence: "EXACT" }
      end
      if (slug = aliases[n]) && Affiliations.valid?(slug)
        return { slug: slug, confidence: "ALIAS" }
      end
      similar(n, options)
    end

    def similar(n, options)
      values = options.flat_map { |o| [ [ o.slug, normalize(o.label) ], [ o.slug, normalize(o.slug) ] ] }.uniq
      list = values.map { |slug, label| "(#{ActiveRecord::Base.connection.quote(slug)}, #{ActiveRecord::Base.connection.quote(label)})" }.join(", ")
      row = ActiveRecord::Base.connection.select_one(<<~SQL)
        SELECT slug, similarity(label, #{ActiveRecord::Base.connection.quote(n)}) AS score
        FROM (VALUES #{list}) AS v(slug, label)
        ORDER BY score DESC LIMIT 1
      SQL
      score = row && row["score"].to_f
      score && score >= THRESHOLD ? { slug: row["slug"], confidence: "SIMILAR", score: score.round(2) } : { slug: nil, confidence: "NONE" }
    end
  end
end
