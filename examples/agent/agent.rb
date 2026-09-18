#!/usr/bin/env ruby
# frozen_string_literal: true

# Galedra example agent: a standalone client with no Rails dependency (spec 04 §11).
#
#   ruby agent.rb keygen > key.json
#   ruby agent.rb run --base-url http://localhost:3000 --key-file key.json --delegation <uuid> [--types A,B] [--domains d] [--once] [--fixtures fixtures.json] [--agent good|bad]
#
# It leases a task, verifies the server's packet signature, answers from
# deterministic fixtures (never heuristics), signs the eir-result-v1 envelope,
# and submits it. Only Ruby's standard library is used; canonical JSON is the
# RFC 8785 subset the ledger uses (no floats; keys sorted by code point).

require "json"
require "net/http"
require "uri"
require "openssl"
require "base64"
require "digest"
require "time"
require "optparse"

module Galedra
  module Jcs
    module_function

    def canonical(value)
      case value
      when Hash then "{" + value.keys.map(&:to_s).sort_by { |k| k.encode("UTF-16BE").unpack("n*") }.map { |k| "#{string(k)}:#{canonical(value.key?(k) ? value[k] : value[k.to_sym])}" }.join(",") + "}"
      when Array then "[" + value.map { |v| canonical(v) }.join(",") + "]"
      when String then string(value)
      when Integer then value.to_s
      when true, false then value.to_s
      when nil then "null"
      when Float then raise ArgumentError, "floats are not allowed in signed payloads"
      when Symbol then string(value.to_s)
      else raise ArgumentError, "unsupported value #{value.class}"
      end
    end

    def string(s)
      out = +'"'
      s.each_char do |c|
        code = c.ord
        out << case c
        when '"' then '\\"'
        when "\\" then "\\\\"
        when "\b" then "\\b"
        when "\f" then "\\f"
        when "\n" then "\\n"
        when "\r" then "\\r"
        when "\t" then "\\t"
        else code < 0x20 ? format("\\u%04x", code) : c
        end
      end
      out << '"'
    end
  end

  module Crypto
    module_function

    def b64(raw) = Base64.urlsafe_encode64(raw, padding: false)
    def unb64(text) = Base64.urlsafe_decode64(text)
    def sha256(bytes) = "sha256:#{Digest::SHA256.hexdigest(bytes)}"
    def hash_json(value) = sha256(Jcs.canonical(value))

    def generate_key
      pkey = OpenSSL::PKey.generate_key("ED25519")
      { "private_key" => b64(pkey.raw_private_key), "public_key" => b64(pkey.raw_public_key), "key_id" => key_id(b64(pkey.raw_public_key)) }
    end

    def key_id(public_key_b64) = "ed25519:#{Digest::SHA256.hexdigest(unb64(public_key_b64))}"

    def sign(private_key_b64, bytes)
      b64(OpenSSL::PKey.new_raw_private_key("ED25519", unb64(private_key_b64)).sign(nil, bytes))
    end

    def verify(public_key_b64, signature_b64, bytes)
      OpenSSL::PKey.new_raw_public_key("ED25519", unb64(public_key_b64)).verify(nil, unb64(signature_b64), bytes)
    rescue OpenSSL::PKey::PKeyError, ArgumentError
      false
    end
  end

  class Client
    SOFTWARE = { "agent_name" => "galedra-example-agent", "version" => "0.1.0", "model_provider" => "stub", "model_id" => "none", "prompt_version" => "fixtures-v1" }.freeze

    attr_reader :key

    # transport: optional lambda (method, path, body_json_or_nil) -> [status, body_string], for in-process use.
    def initialize(base_url:, key_file:, delegation_id: nil, transport: nil, software: SOFTWARE)
      @base = base_url.sub(%r{/\z}, "")
      @key = key_file.is_a?(Hash) ? key_file : JSON.parse(File.read(key_file))
      @delegation_id = delegation_id
      @transport = transport
      @software = software
    end

    def key_id = @key["key_id"]

    def meta
      @meta ||= get("/api/v1/meta")
    end

    def register(kind: "AGENT", display_name: nil)
      payload = { "public_key" => @key["public_key"], "kind" => kind, "display_name" => display_name }.compact
      post_contribution(envelope("REGISTER_KEY", payload, delegation: false))
    end

    def lease_next(types: [], domains: [])
      body = signed_request("eir-lease-v1", { "types" => types, "domains" => domains })
      status, text = request(:post, "/api/v1/tasks/next", body)
      return nil if status == 204
      raise "lease failed (#{status}): #{text}" unless status == 200

      JSON.parse(text)
    end

    def release(task_id)
      status, text = request(:post, "/api/v1/tasks/#{task_id}/release", signed_request("eir-lease-v1", {}))
      raise "release failed (#{status}): #{text}" unless status == 200

      JSON.parse(text)
    end

    def verify_packet!(packet)
      unsigned = packet.reject { |k, _| k == "server_signature" }
      raise "packet is not signed by the ledger's system key" unless packet["server_key_id"] == meta["system_key_id"] &&
        Crypto.verify(meta["system_public_key"], packet["server_signature"], Crypto.hash_json(unsigned))
      packet
    end

    def submit(packet, outcome:, ops:)
      payload = { "outcome" => outcome, "ops" => ops }
      unsigned = {
        "protocol" => "eir-result-v1", "action_type" => "TASK_RESULT", "task_id" => packet["task_id"],
        "task_packet_hash" => Crypto.hash_json(packet.reject { |k, _| k == "server_signature" }),
        "contributor_key_id" => key_id, "delegation_id" => @delegation_id, "client_created_at" => Time.now.utc.iso8601,
        "software" => @software, "payload" => payload, "payload_hash" => Crypto.hash_json(payload)
      }.compact
      post_contribution(unsigned.merge("signature" => Crypto.sign(@key["private_key"], Jcs.canonical(unsigned))))
    end

    def envelope(action_type, payload, delegation: true)
      unsigned = { "protocol" => "eir-contribution-v1", "action_type" => action_type, "signer_key_id" => key_id,
                   "delegation_id" => (delegation ? @delegation_id : nil), "client_created_at" => Time.now.utc.iso8601,
                   "payload" => payload, "payload_hash" => Crypto.hash_json(payload) }.compact
      unsigned.merge("signature" => Crypto.sign(@key["private_key"], Jcs.canonical(unsigned)))
    end

    def post_contribution(envelope)
      status, text = request(:post, "/api/v1/contributions", envelope)
      raise "contribution rejected (#{status}): #{text}" unless [ 200, 201 ].include?(status)

      JSON.parse(text)
    end

    private

    def signed_request(protocol, payload)
      unsigned = { "protocol" => protocol, "signer_key_id" => key_id, "delegation_id" => @delegation_id,
                   "client_created_at" => Time.now.utc.iso8601, "payload" => payload }.compact
      unsigned.merge("signature" => Crypto.sign(@key["private_key"], Jcs.canonical(unsigned)))
    end

    def get(path)
      status, text = request(:get, path, nil)
      raise "GET #{path} failed (#{status})" unless status == 200

      JSON.parse(text)
    end

    def request(method, path, body)
      return @transport.call(method, path, body && JSON.generate(body)) if @transport

      uri = URI("#{@base}#{path}")
      req = method == :get ? Net::HTTP::Get.new(uri) : Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
      req.body = JSON.generate(body) if body
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
      [ res.code.to_i, res.body.to_s ]
    end
  end

  # Deterministic answers from fixtures. A fixture matches on task_type and an
  # optional claim_text_includes, and names a behaviour with parameters.
  class StubVerifier
    def initialize(fixtures, agent: "good")
      @fixtures = fixtures.select { |f| (f["agent"] || "good") == agent }
    end

    def run(packet)
      fixture = @fixtures.find { |f| matches?(f["match"], packet) }
      return { "outcome" => "CANNOT_DETERMINE", "ops" => [] } if fixture.nil?

      send("behaviour_#{fixture['behaviour']}", packet, fixture.fetch("params", {}))
    end

    def matches?(match, packet)
      return false unless match["task_type"] == packet["task_type"]

      text = packet.dig("target", "claim_text") || packet.dig("target", "title") || ""
      match["claim_text_includes"].nil? || text.include?(match["claim_text_includes"])
    end

    def behaviour_none_found(_packet, _params) = { "outcome" => "NONE_FOUND", "ops" => [] }
    def behaviour_no_claims(_packet, _params) = { "outcome" => "NO_CLAIMS", "ops" => [] }
    def behaviour_none_material(_packet, _params) = { "outcome" => "NONE_MATERIAL", "ops" => [] }

    # EVIDENCE_VERIFICATION: create evidence on the packet's location and link it.
    def behaviour_confirm_direct(packet, params)
      ctx = packet["context"]
      { "outcome" => params.fetch("outcome", "CONFIRMED"), "ops" => [
        { "op" => "CREATE_EVIDENCE", "ref" => "ev", "source_location_id" => ctx["source_location_id"], "observation_type" => params.fetch("observation_type", "DIRECT_TEXT"),
          "statement" => params.fetch("statement", "The excerpt states it.") },
        { "op" => "LINK_EVIDENCE", "evidence_item_id" => "ev", "claim_id" => packet.dig("target", "claim_id"), "direction" => params.fetch("direction", "SUPPORT"),
          "relevance_strength" => params.fetch("relevance_strength", "DIRECT"), "interpretive_steps" => params.fetch("interpretive_steps", 0),
          "note" => params["note"] }.compact
      ] }
    end

    # EVIDENCE_VERIFICATION: link an evidence item already on the packet's location (by statement fragment, else the first).
    def behaviour_confirm_existing(packet, params)
      existing = packet.dig("context", "existing_evidence") || []
      item = existing.find { |e| params["statement_includes"] && e["statement"].to_s.include?(params["statement_includes"]) } || existing.first
      return behaviour_confirm_direct(packet, params) if item.nil?

      { "outcome" => params.fetch("outcome", "CONFIRMED"), "ops" => [
        { "op" => "LINK_EVIDENCE", "evidence_item_id" => item["evidence_item_id"], "claim_id" => packet.dig("target", "claim_id"), "direction" => params.fetch("direction", "SUPPORT"),
          "relevance_strength" => params.fetch("relevance_strength", "DIRECT"), "interpretive_steps" => params.fetch("interpretive_steps", 0), "note" => params["note"] }.compact
      ] }
    end

    # SOURCE_INDEPENDENCE_CHECK: assign evidence whose source title matches to one group (existing by description, else new).
    def behaviour_group_by_title(packet, params)
      ctx = packet["context"]
      patterns = Array(params["source_title_includes"])
      items = ctx["counted_evidence"].select { |e| patterns.any? { |p| e.dig("source", "title").to_s.include?(p) } }
      return { "outcome" => "INDEPENDENT", "ops" => [] } if items.empty?

      existing = ctx["existing_groups"].find { |g| params["group_description"] && g["description"] == params["group_description"] }
      ops = []
      group_ref = existing ? existing["independence_group_id"] : "grp"
      ops << { "op" => "CREATE_INDEPENDENCE_GROUP", "ref" => "grp", "group_type" => params.fetch("group_type", "OTHER"), "description" => params["group_description"] } unless existing
      items.reject { |e| e["independence_group_id"] == group_ref }.each do |e|
        ops << { "op" => "ASSIGN_INDEPENDENCE_GROUP", "evidence_item_id" => e["evidence_item_id"], "independence_group_id" => group_ref }
      end
      { "outcome" => "GROUPED", "ops" => ops }
    end

    # QUALIFIER_CHECK (the public demo): a qualifying evidence item on the dataset location,
    # a QUALIFY link, an edge from the narrower candidate claim, and weakened supersessions.
    def behaviour_qualifier_demo(packet, params)
      ctx = packet["context"]
      target = packet.dig("target", "claim_id")
      dataset = ctx["counted_links"].find { |l| l["source_type"] == params.fetch("qualifier_source_type", "DATASET") }
      ops = []
      if dataset
        ops << { "op" => "CREATE_EVIDENCE", "ref" => "qual", "source_location_id" => dataset["source_location_id"], "observation_type" => "DATASET_RESULT", "statement" => params.fetch("statement", "The sample was limited.") }
        ops << { "op" => "LINK_EVIDENCE", "evidence_item_id" => "qual", "claim_id" => target, "direction" => "QUALIFY", "relevance_strength" => "DIRECT", "interpretive_steps" => 0 }
      end
      narrower = ctx.fetch("candidate_claims", []).find { |c| params["narrower_claim_includes"] && c["claim_text"].include?(params["narrower_claim_includes"]) }
      ops << { "op" => "CREATE_CLAIM_EDGE", "from_claim_id" => narrower["claim_id"], "to_claim_id" => target, "relationship_type" => "NARROWS" } if narrower
      ctx["counted_links"].select { |l| l["direction"] == "SUPPORT" }.each do |l|
        ops << { "op" => "SUPERSEDE_LINK", "link_id" => l["link_id"], "direction" => "SUPPORT", "relevance_strength" => params.fetch("weakened_strength", "WEAK"),
                 "interpretive_steps" => params.fetch("weakened_steps", 3), "reason" => params.fetch("reason", "omitted qualifier") }
      end
      { "outcome" => ops.empty? ? "NONE_MATERIAL" : "QUALIFIERS_FOUND", "ops" => ops }
    end

    # CLAIM_EXTRACTION: propose the fixture's claims verbatim.
    def behaviour_propose_claims(_packet, params)
      ops = Array(params["claims"]).map do |c|
        { "op" => "CREATE_CLAIM", "canonical_text" => c["text"], "claim_type" => c["type"], "affirms_not_private_individual" => true }
      end
      { "outcome" => ops.empty? ? "NO_CLAIMS" : "CLAIMS_FOUND", "ops" => ops }
    end
  end

  module CLI
    module_function

    def main(argv)
      command = argv.shift
      case command
      when "keygen" then puts JSON.pretty_generate(Crypto.generate_key)
      when "run" then run(argv)
      when "investigate" then investigate(argv)
      else
        warn "usage: agent.rb keygen | agent.rb run --base-url URL --key-file FILE --delegation ID [--types A,B] [--domains d] [--once] [--fixtures FILE] [--agent good|bad]"
        warn "       agent.rb investigate --base-url URL --token TOKEN [--bundle FILE]"
        exit 2
      end
    end

    # Stage 13: post an investigation bundle with an assistant token (a
    # connected assistant's bearer token from /assistants/new) and print the
    # plain headline and link for each claim. The default bundle is a
    # fictional social-media post checked against a quoted source.
    def investigate(argv)
      options = { bundle: File.join(__dir__, "investigation.json") }
      OptionParser.new do |o|
        o.on("--base-url URL") { |v| options[:base_url] = v }
        o.on("--token TOKEN") { |v| options[:token] = v }
        o.on("--bundle FILE") { |v| options[:bundle] = v }
      end.parse!(argv)
      bundle = JSON.parse(File.read(options[:bundle]))
      bundle.each_value { |list| list.each { |item| item["retrieved_at"] ||= Time.now.utc.iso8601 if item.is_a?(Hash) && item.key?("content_hash") } if list.is_a?(Array) }
      status, text = Investigator.post(options.fetch(:base_url), options.fetch(:token), bundle)
      body = JSON.parse(text)
      if status == 409
        puts "similar claims already exist; add attach_to or on_duplicate: create"
        body["existing"].each { |handle, list| list.each { |c| puts "  #{handle}: #{c['text']} (#{c['similarity']}) #{c['url']}" } }
        exit 1
      end
      raise "investigation rejected (#{status}): #{text}" unless status == 201

      body["claims"].each do |c|
        puts "#{c['handle']}: #{c.dig('card', 'plain', 'headline')} #{c['url']}"
        puts "  say instead: #{c.dig('card', 'plain', 'say_instead')}" if c.dig("card", "plain", "say_instead")
      end
      puts "#{body['contributions']} contributions, #{body['tasks_opened']} verification tasks opened"
    end


    def run(argv)
      options = { types: [], domains: [], fixtures: File.join(__dir__, "fixtures.json"), agent: "good", once: false }
      OptionParser.new do |o|
        o.on("--base-url URL") { |v| options[:base_url] = v }
        o.on("--key-file FILE") { |v| options[:key_file] = v }
        o.on("--delegation ID") { |v| options[:delegation] = v }
        o.on("--types LIST") { |v| options[:types] = v.split(",") }
        o.on("--domains LIST") { |v| options[:domains] = v.split(",") }
        o.on("--fixtures FILE") { |v| options[:fixtures] = v }
        o.on("--agent NAME") { |v| options[:agent] = v }
        o.on("--once") { options[:once] = true }
      end.parse!(argv)
      client = Client.new(base_url: options.fetch(:base_url), key_file: options.fetch(:key_file), delegation_id: options[:delegation])
      verifier = StubVerifier.new(JSON.parse(File.read(options[:fixtures])), agent: options[:agent])
      loop do
        lease = client.lease_next(types: options[:types], domains: options[:domains])
        if lease.nil?
          puts "no task available"
          break
        end
        packet = client.verify_packet!(lease["packet"])
        answer = verifier.run(packet)
        result = client.submit(packet, outcome: answer["outcome"], ops: answer["ops"])
        puts "task #{packet['task_id']} (#{packet['task_type']}): #{answer['outcome']} -> seq #{result.dig('contribution', 'seq')} #{result['acceptance'] ? 'accepted' : 'pending'}"
        break if options[:once]
      end
    end
  end
  module Investigator
    module_function

    def post(base_url, token, bundle)
      uri = URI("#{base_url.sub(%r{/\z}, '')}/api/v1/investigations")
      req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Authorization" => "Bearer #{token}")
      req.body = JSON.generate(bundle)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
      [ res.code.to_i, res.body.to_s ]
    end
  end
end

Galedra::CLI.main(ARGV) if $PROGRAM_NAME == __FILE__
