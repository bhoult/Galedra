# frozen_string_literal: true

module Crypto
  # SHA-256 content addressing, always written with the "sha256:" prefix and
  # lowercase hex (spec 02 §6).
  module Hashing
    PREFIX = "sha256:"
    FORMAT = /\Asha256:\h{64}\z/

    # Hash of raw bytes (blobs, canonical text already produced).
    def self.bytes(data)
      "#{PREFIX}#{Digest::SHA256.hexdigest(data)}"
    end

    # Hash of the RFC 8785 canonical form of a JSON-compatible value.
    def self.json(value)
      bytes(Crypto::CanonicalJson.call(value))
    end

    def self.valid?(string)
      FORMAT.match?(string.to_s)
    end
  end
end
