# frozen_string_literal: true

module Llm
  # The deterministic boundary for functions the spec once called "LLM:
  # optional" (07 Phase 8, 10). Galedra runs no model (CLAUDE.md Invariant 18):
  # the stub is the only adapter, and no adapter that calls a model is added
  # here. A function that needs a model becomes a task or a tool for a
  # connected assistant, whose answer is a signed contribution open to audit.
  #
  # Claim extraction was here until Stage 46: a sentence splitter behind
  # extract_claims proposed the claims for Analyze text. It split on
  # punctuation and guessed types from keywords, which is not a breakdown, and
  # it is gone; Analyze text opens CLAIM_EXTRACTION tasks instead.
  module Adapter
    ENV_KEY = "LEDGER_LLM_ADAPTER"

    def self.current
      case ENV.fetch(ENV_KEY, "stub")
      when "stub" then StubAdapter.new
      else raise ArgumentError, "unknown #{ENV_KEY}=#{ENV[ENV_KEY]}; only 'stub' exists in P0"
      end
    end
  end

  # Deterministic, template-based implementation.
  class StubAdapter
    NAME = "stub-v0.1"

    def name = NAME

    # input: Summaries::Input hash. Returns [{"text" =>, "cites" => []}].
    def summarize(input, type:)
      Summaries::StubGenerator.sentences(input, type: type)
    end

    # Maps a requested affiliation to an existing one: {slug:, confidence:}
    # with confidence EXACT, ALIAS, SIMILAR, or NONE (Affiliations::Resolve).
    def resolve_affiliation(text)
      Affiliations::Resolve.call(text)
    end
  end
end
