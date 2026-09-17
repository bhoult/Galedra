# frozen_string_literal: true

module Scoring
  # The score trace (spec 03 §10): canonical JSON with every number as a
  # fixed-place string, hashed into trace_hash.
  module Trace
    module_function

    def canonical(trace)
      Crypto::CanonicalJson.call(trace)
    end

    def hash(trace)
      Crypto::Hashing.json(trace)
    end
  end
end
