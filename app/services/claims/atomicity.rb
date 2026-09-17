# frozen_string_literal: true

module Claims
  # Heuristic atomicity check (spec 02 §4): warnings for the UI and API, never
  # a block. Claims should be the smallest independently evaluable propositions.
  module Atomicity
    MAX_WORDS = 25
    CLAUSE_JOINERS = /\b(?:and|but|or|nor|yet)\b/i
    INFERENCE_WORDS = /\b(?:so|therefore|thus|hence|because|since)\b/i

    def self.warnings(text)
      text = text.to_s
      words = text.split
      warnings = []
      if words.size > MAX_WORDS
        warnings << { code: "ATOMICITY_LONG", detail: "#{words.size} words; atomic claims are usually under #{MAX_WORDS}" }
      end
      parts = text.split(CLAUSE_JOINERS)
      if parts.size > 1 && parts.count { |part| part.split.size >= 3 } >= 2
        warnings << { code: "ATOMICITY_CONJUNCTION", detail: "a conjunction joins clauses that may be separately evaluable" }
      end
      if text.count(",") >= 2
        warnings << { code: "ATOMICITY_SERIAL", detail: "a comma-separated series may list several propositions" }
      end
      if INFERENCE_WORDS.match?(text)
        warnings << { code: "ATOMICITY_INFERENCE", detail: "an inference word joins a premise to a conclusion; consider separate claims and an edge" }
      end
      warnings
    end
  end
end
