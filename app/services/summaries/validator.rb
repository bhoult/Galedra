# frozen_string_literal: true

module Summaries
  # Every sentence cites at least one id, and every cite is in the input set
  # (spec 04 §10). Anything else is rejected and the stub is served instead.
  module Validator
    Invalid = Class.new(StandardError)
    MAX = { "SHORT" => 2, "STANDARD" => 6 }.freeze

    module_function

    def validate!(sentences, input, type:)
      allowed = Input.cite_set(input)
      raise Invalid, "expected an array of sentences" unless sentences.is_a?(Array) && sentences.any?
      raise Invalid, "#{type} allows at most #{MAX.fetch(type)} sentences" if sentences.size > MAX.fetch(type)
      sentences.each_with_index do |s, i|
        raise Invalid, "sentence #{i} must have text and cites" unless s.is_a?(Hash) && s["text"].is_a?(String) && s["text"].present? && s["cites"].is_a?(Array)
        raise Invalid, "sentence #{i} cites nothing" if s["cites"].empty?
        unknown = s["cites"] - allowed
        raise Invalid, "sentence #{i} cites unknown ids: #{unknown.join(', ')}" if unknown.any?
      end
      sentences
    end

    def valid?(sentences, input, type:)
      validate!(sentences, input, type: type)
      true
    rescue Invalid
      false
    end
  end
end
