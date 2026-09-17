# frozen_string_literal: true

module Governance
  # The constitution (CONSTITUTION.md, a verbatim copy of the spec's
  # 12-constitution.md) and its integrity hash, published by GET /api/v1/meta
  # so anyone can check which principles a running ledger claims to follow.
  class Constitution
    PATH = Rails.root.join("CONSTITUTION.md")
    VERSION_PATTERN = /^\| Version \| (\d+\.\d+\.\d+)/

    def self.call = new.to_h

    def bytes
      @bytes ||= File.binread(PATH)
    end

    def digest
      "sha256:#{Digest::SHA256.hexdigest(bytes)}"
    end

    def version
      bytes[VERSION_PATTERN, 1]
    end

    def to_h
      { version: version, hash: digest }
    end
  end
end
