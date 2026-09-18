# frozen_string_literal: true

module Claims
  # The stub claim extractor behind Llm::Adapter (spec 06 §5 Analyze text):
  # deterministic sentence splitting and a type guess from surface cues, plus a
  # separate TEXTUAL claim for each parenthetical citation. Proposals only; a
  # human edits, splits, types, and accepts them.
  module Extract
    CITATION = /\s*\(([^()]+?),\s*(\d{4})\)/
    RULES = [
      [ /\b(should|ought|must|need to)\b/i, "NORMATIVE" ],
      [ /\b(causes?|caused|boosts?|leads? to|results? in|drives?|because)\b/i, "CAUSAL" ],
      [ /\bwill\b/i, "FORECAST" ],
      [ /\d+(\.\d+)?%|\b\d{2,}\b/, "QUANTITATIVE" ],
      [ /\b(reports? that|says?|states?|according to|claims? that|wrote)\b/i, "TEXTUAL" ]
    ].freeze

    module_function

    def call(text)
      sentences(text).flat_map do |sentence|
        proposals = []
        if (m = sentence.match(CITATION))
          bare = sentence.sub(CITATION, "").strip
          proposals << { "canonical_text" => finish(bare), "claim_type" => guess(bare) }
          proposals << { "canonical_text" => finish("#{m[1].strip} (#{m[2]}) reports that #{bare.sub(/\A[A-Z]/) { |c| c.downcase }}"), "claim_type" => "TEXTUAL" }
        else
          proposals << { "canonical_text" => finish(sentence), "claim_type" => guess(sentence) }
        end
        proposals.each { |p| p["warnings"] = Atomicity.warnings(p["canonical_text"]) }
      end
    end

    def sentences(text)
      text.to_s.gsub(/\s+/, " ").split(/(?<=[.!?])\s+|\s*;\s+|:\s+(?=[A-Z0-9])/).map(&:strip).reject(&:empty?)
    end

    def guess(sentence)
      RULES.each { |pattern, type| return type if pattern.match?(sentence) }
      "OBSERVATIONAL"
    end

    def finish(s)
      s = s.strip
      s.end_with?(".", "!", "?") ? s : "#{s}."
    end
  end
end
