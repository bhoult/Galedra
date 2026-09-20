# frozen_string_literal: true

module Mcp
  # Which revision one request is speaking (Stage 32).
  #
  # MCP split in two at revision 2026-07-28. Everything up to 2025-11-25 is
  # *legacy*: a client calls `initialize` once, and the version, identity and
  # capabilities agreed there hold for the session. 2026-07-28 is *modern*: there
  # is no handshake at all, every request carries its own version, identity and
  # capabilities in `_meta`, and the server holds no session state.
  #
  # Galedra serves both on the same endpoint, which the spec permits and which is
  # not optional in practice: claude.ai is a legacy client today, so dropping the
  # handshake would disconnect every assistant already connected. The spec gives
  # the rule for choosing, and this class is only that rule: a request carrying
  # modern per-request `_meta` is served as modern, and anything else is served
  # exactly as it was before this class existed.
  #
  # Declaring a version is therefore what selects modern, not the mere presence
  # of the header: a legacy client sends `MCP-Protocol-Version: 2025-06-18` on
  # every request after its handshake, and that must keep meaning what it meant.
  class Era
    MODERN = "2026-07-28"
    LEGACY = "2025-06-18"
    SUPPORTED = [ MODERN, LEGACY ].freeze
    MODERN_VERSIONS = [ MODERN ].freeze

    VERSION_KEY = "io.modelcontextprotocol/protocolVersion"
    CLIENT_INFO_KEY = "io.modelcontextprotocol/clientInfo"
    CAPABILITIES_KEY = "io.modelcontextprotocol/clientCapabilities"
    SERVER_INFO_KEY = "io.modelcontextprotocol/serverInfo"

    HEADER_MISMATCH = -32020
    MISSING_CAPABILITY = -32021
    UNSUPPORTED_VERSION = -32022
    INVALID_PARAMS = -32602

    # `=?base64?...?=` wraps a header value that cannot be sent as plain ASCII.
    SENTINEL = /\A=\?base64\?(.*)\?=\z/

    attr_reader :version, :error, :client_info

    def self.legacy = new(message: {})

    def initialize(message:, protocol_version: nil, mcp_method: nil, mcp_name: nil)
      @message = message.is_a?(Hash) ? message : {}
      @params = @message["params"].is_a?(Hash) ? @message["params"] : {}
      @meta = @params["_meta"].is_a?(Hash) ? @params["_meta"] : {}
      @header_version = protocol_version.presence
      @mcp_method = mcp_method.presence
      @mcp_name = mcp_name.presence
      @meta_version = @meta[VERSION_KEY].presence
      # Carrying a protocol version in params._meta IS the modern mechanism, so
      # it selects the modern path whatever version it names: an unknown one
      # then gets -32022 and a list of what this server serves, rather than
      # being quietly answered with legacy shapes it did not ask for.
      @modern = @meta_version.present? || MODERN_VERSIONS.include?(@header_version)
      @version = @modern ? @meta_version : (@header_version || LEGACY)
      @client_info = @meta[CLIENT_INFO_KEY]
      @error = @modern ? validate : nil
    end

    def modern? = @modern

    # Status for a rejected request: modern validation failures are 400, per the
    # transport's server-validation rules.
    def error_status = 400

    private

    def validate
      return fail_with(INVALID_PARAMS, "missing #{VERSION_KEY} in params._meta") if @meta_version.nil?
      unless MODERN_VERSIONS.include?(@meta_version)
        return fail_with(UNSUPPORTED_VERSION, "unsupported protocol version",
                         { supported: SUPPORTED, requested: @meta_version })
      end
      return fail_with(HEADER_MISMATCH, "missing required header MCP-Protocol-Version") if @header_version.nil?
      unless @header_version == @meta_version
        return fail_with(HEADER_MISMATCH, "MCP-Protocol-Version header #{@header_version.inspect} does not match body value #{@meta_version.inspect}")
      end
      unless @meta.key?(CAPABILITIES_KEY)
        return fail_with(INVALID_PARAMS, "missing #{CAPABILITIES_KEY} in params._meta")
      end
      validate_headers
    end

    # Mcp-Method and Mcp-Name mirror body fields so an intermediary can route
    # without parsing the body. The server must reject any disagreement, because
    # a proxy acting on the header while the server acts on the body is the
    # vulnerability these headers would otherwise introduce.
    def validate_headers
      method = @message["method"].to_s
      return fail_with(HEADER_MISMATCH, "missing required header Mcp-Method") if @mcp_method.nil?
      return fail_with(HEADER_MISMATCH, "Mcp-Method header #{@mcp_method.inspect} does not match body method #{method.inspect}") if @mcp_method != method

      expected = @params["name"] || @params["uri"]
      return nil unless %w[tools/call resources/read prompts/get].include?(method)
      return fail_with(HEADER_MISMATCH, "missing required header Mcp-Name") if @mcp_name.nil?
      given = decode(@mcp_name)
      return fail_with(HEADER_MISMATCH, "Mcp-Name header #{given.inspect} does not match body value #{expected.inspect}") if given != expected.to_s

      nil
    end

    def decode(value)
      match = SENTINEL.match(value)
      return value unless match

      Base64.strict_decode64(match[1]).force_encoding(Encoding::UTF_8)
    rescue ArgumentError
      value
    end

    def fail_with(code, message, data = nil)
      { code: code, message: message }.tap { |e| e[:data] = data if data }
    end
  end
end
