# frozen_string_literal: true

module Ledger
  # This node's identity (spec 14 §5–§7, §25): the public address it answers at
  # and the system key that signs every entry and checkpoint. Federation is not
  # built; this is the one place that says who "this node" is, so keys,
  # checkpoints, and exports can name it. LEDGER_NODE_URL sets the address;
  # otherwise the first allowed host over https, or localhost in development.
  module Node
    URL_ENV = "LEDGER_NODE_URL"
    HOSTS_ENV = "LEDGER_ALLOWED_HOSTS"
    LICENSE_ENV = "LEDGER_DATA_LICENSE"
    SCHEMA_VERSION = "eir-schema-v1"
    CHECKPOINT_PROTOCOL = "eir-checkpoint-v1"
    VISIBILITIES = %w[PUBLIC].freeze

    module_function

    def url
      explicit = ENV[URL_ENV].presence
      return explicit.chomp("/") if explicit

      host = ENV.fetch(HOSTS_ENV, "").split(",").map(&:strip).reject { |h| h.empty? || h.start_with?(".") }.first
      return "https://#{host}" if host

      Rails.env.production? ? nil : "http://localhost:3000"
    end

    def key_id
      Crypto::SystemKey.configured? ? Crypto::SystemKey.key_id : nil
    end

    # The licence the public database is offered under: ODbL-1.0, adopted by
    # the owner on 2026-09-19 (NOTICE), unless the node sets another.
    DEFAULT_DATA_LICENSE = "ODbL-1.0"

    def data_license
      ENV[LICENSE_ENV].presence || DEFAULT_DATA_LICENSE
    end

    def to_h
      { url: url, key_id: key_id, protocol: Ledger::PROTOCOL, schema_version: SCHEMA_VERSION,
        checkpoint_protocol: CHECKPOINT_PROTOCOL, data_license: data_license, visibilities: VISIBILITIES,
        software: Governance::Software.to_h }
    end

    # A key's home: the node it was registered on. Null on the projection
    # means this node, so a mirror reads it as the origin it copied from.
    def home_url_for(contributor)
      contributor.home_url.presence || url
    end
  end
end
