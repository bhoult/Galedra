# frozen_string_literal: true

module Llm
  # The optional LLM boundary (spec 07 Phase 8, 10 "LLM: optional"). The stub
  # is the default and the only P0 implementation; a real adapter must produce
  # the same shapes and pass the same validators.
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

    # Returns [{"canonical_text" =>, "claim_type" =>}] proposals for Analyze text.
    def extract_claims(text)
      Claims::Extract.call(text)
    end

    # Maps a requested affiliation to an existing one: {slug:, confidence:}
    # with confidence EXACT, ALIAS, SIMILAR, or NONE (Affiliations::Resolve).
    def resolve_affiliation(text)
      Affiliations::Resolve.call(text)
    end
  end
end
