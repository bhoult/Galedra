# frozen_string_literal: true

require "json/canonicalization"

module Crypto
  # RFC 8785 (JSON Canonicalization Scheme). Every hash and signature in the
  # ledger is computed over this serialization (spec 02 §6, 05 §3).
  module CanonicalJson
    # Canonical text for a ledger value. Symbol keys become strings. Floats are
    # rejected because signed payloads never contain them (spec README
    # conventions): use integers or decimal strings.
    def self.call(value)
      reject_floats!(value)
      serialize(value)
    end

    # Plain RFC 8785 serialization with no ledger policy applied. Exists so the
    # RFC's own test vectors (which contain floats) can be checked.
    def self.serialize(value)
      value.to_json_c14n
    end

    def self.reject_floats!(value, path = "$")
      case value
      when Float
        raise ArgumentError, "float at #{path}: use an integer or a decimal string"
      when Hash
        value.each { |k, v| reject_floats!(v, "#{path}.#{k}") }
      when Array
        value.each_with_index { |v, i| reject_floats!(v, "#{path}[#{i}]") }
      end
    end
    private_class_method :reject_floats!
  end
end
