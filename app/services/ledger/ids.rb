# frozen_string_literal: true

module Ledger
  # Deterministic ids for projection rows. A row created by contribution C is
  # given the same id on every replay, which is what makes "truncate, replay,
  # identical rows" (spec 02 §1.1 rule 3) possible. Log rows themselves keep
  # UUIDv7. The result is a UUID with version nibble 8 (RFC 9562 custom).
  module Ids
    def self.derive(*parts)
      bytes = Digest::SHA256.digest(parts.join(":"))[0, 16].bytes
      bytes[6] = (bytes[6] & 0x0f) | 0x80
      bytes[8] = (bytes[8] & 0x3f) | 0x80
      hex = bytes.pack("C*").unpack1("H*")
      [ hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12] ].join("-")
    end
  end
end
