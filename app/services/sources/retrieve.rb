# frozen_string_literal: true

module Sources
  # Stage 17: Galedra fetches a source held by reference under its own rules,
  # hashes what it received, looks for each quoted excerpt, and appends what it
  # found as a system-signed RETRIEVE_SOURCE. The only input is a link already
  # in the log. Rules: public hosts only (the address is refused after DNS
  # resolution when it is private, loopback, link-local, or a metadata range,
  # and re-checked on every redirect); http or https; at most five redirects;
  # a byte cap and a timeout; a fixed user agent; robots exclusions respected;
  # one fetch per host per minute; no script execution. Page text is never
  # stored. LEDGER_RETRIEVAL turns it off (default off in test).
  module Retrieve
    ENV_KEY = "LEDGER_RETRIEVAL"
    MAX_BYTES = 2 * 1024 * 1024
    MAX_REDIRECTS = 5
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    HOST_INTERVAL = 60
    TEXT_TYPES = %w[text/html application/xhtml+xml text/plain text/markdown application/json text/xml application/xml].freeze

    Response = Struct.new(:status, :media_type, :body, :final_url, :too_large, keyword_init: true)

    class Refused < StandardError; end

    module_function

    def enabled?
      ENV.fetch(ENV_KEY, Rails.env.test? ? "off" : "on") == "on"
    end

    def user_agent
      "Galedra/#{Governance::Software.revision} (+#{Ledger::Node.url || 'https://github.com/bhoult/Galedra'}; source retrieval)"
    end

    # Fetches and records. Returns the appended contribution, or nil when the
    # source has stored content or was already retrieved at this created_seq
    # (unless force).
    def call(source, fetcher: Fetcher.new, force: false)
      return nil unless source.content.nil? && source.canonical_uri.present?
      return nil if !force && SourceRetrieval.exists?(source_id: source.id, source_created_seq: source.created_seq)

      # Microseconds: two fetches in one second must not collapse into one idempotent entry.
      payload = attempt(source, fetcher).merge("source_id" => source.id, "fetched_at" => Time.now.utc.iso8601(6))
      envelope = Contributions::Envelope.build(action_type: "RETRIEVE_SOURCE", payload: payload.compact, key_pair: Crypto::SystemKey.key_pair)
      Ledger::Append.call(envelope, custody: Crypto::Custody::SYSTEM).contribution
    end

    # The payload minus source and time: outcome, hash, size, type, final url, excerpts.
    def attempt(source, fetcher)
      locations = source.source_locations.live.where(locator_type: %w[QUOTE TRANSCRIPTION]).order(:created_seq).to_a
      uri = URI.parse(source.canonical_uri) rescue nil
      return { "outcome" => "UNSUPPORTED" } unless uri.is_a?(URI::HTTP) && uri.host.present?

      response = fetcher.get(uri)
      return { "outcome" => response.status, "final_url" => response.final_url } if response.status != "FETCHED"

      body = response.body.to_s.b
      out = { "outcome" => "FETCHED", "content_hash" => Crypto::Hashing.bytes(body), "content_length" => body.bytesize,
              "media_type" => response.media_type, "final_url" => response.final_url }
      out["excerpts"] = findings(source, locations, body, response.media_type)
      out
    rescue Refused => e
      { "outcome" => "REFUSED", "final_url" => e.message }
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
      { "outcome" => "TIMEOUT" }
    rescue SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError
      { "outcome" => "NOT_FOUND" }
    end

    def findings(source, locations, body, media_type)
      textual = TEXT_TYPES.any? { |t| media_type.to_s.start_with?(t) } && source.source_type != "IMAGE"
      return locations.map { |l| { "location_id" => l.id, "found" => "UNSUPPORTED" } } unless textual

      text = extract_text(body, media_type)
      normalized_text = normalize(text)
      locations.map do |l|
        excerpt = l.excerpt.to_s
        found = if excerpt.strip.empty? then "UNSUPPORTED"
        elsif text.include?(excerpt) then "VERBATIM"
        elsif normalized_text.include?(normalize(excerpt)) then "NORMALIZED"
        else "NOT_FOUND"
        end
        { "location_id" => l.id, "found" => found }
      end
    end

    # Served HTML is read as text after dropping scripts, styles, and tags.
    def extract_text(body, media_type)
      text = body.dup.force_encoding("UTF-8")
      text = text.scrub("�")
      if media_type.to_s.start_with?("text/html", "application/xhtml+xml")
        text = text.gsub(%r{<(script|style|noscript)\b[^>]*>.*?</\1\s*>}mi, " ").gsub(/<!--.*?-->/m, " ").gsub(/<[^>]+>/, " ")
        text = CGI.unescapeHTML(decode_named_entities(text))
      end
      text.gsub(/[[:space:]]+/, " ").strip
    end

    # CGI.unescapeHTML knows only the five basic and numeric entities.
    NAMED_ENTITIES = { "nbsp" => " ", "ensp" => " ", "emsp" => " ", "thinsp" => " ", "ndash" => "\u2013", "mdash" => "\u2014", "lsquo" => "\u2018", "rsquo" => "\u2019",
                       "sbquo" => "\u201a", "ldquo" => "\u201c", "rdquo" => "\u201d", "bdquo" => "\u201e", "hellip" => "\u2026", "apos" => "'", "laquo" => "\u00ab", "raquo" => "\u00bb",
                       "copy" => "\u00a9", "reg" => "\u00ae", "trade" => "\u2122", "deg" => "\u00b0", "middot" => "\u00b7", "bull" => "\u2022", "times" => "\u00d7", "minus" => "\u2212",
                       "eacute" => "\u00e9", "egrave" => "\u00e8", "agrave" => "\u00e0", "ccedil" => "\u00e7", "uuml" => "\u00fc", "ouml" => "\u00f6", "auml" => "\u00e4", "ntilde" => "\u00f1", "szlig" => "\u00df" }.freeze

    def decode_named_entities(text)
      text.gsub(/&([a-zA-Z]+);/) { NAMED_ENTITIES.fetch($1, $&) }
    end

    def normalize(s)
      s.to_s.unicode_normalize(:nfkc).downcase.tr("\u2018\u2019\u201a\u201b\u2032", "'").tr("\u201c\u201d\u201e\u201f\u2033", '"').tr("\u2010\u2011\u2012\u2013\u2014\u2015\u2212", "-")
       .gsub(/[[:space:]]+/, " ").strip
    end

    # Address safety (spec 04 §6 step 9): resolve first, connect only to public addresses.
    def refuse_private!(host, resolver: Resolv)
      addresses = resolver.getaddresses(host)
      raise Refused, "#{host}: no address" if addresses.empty?

      addresses.each do |a|
        ip = IPAddr.new(a)
        raise Refused, "#{host} resolves to a non-public address" if private_address?(ip)
      end
      addresses
    end

    PRIVATE_RANGES = %w[0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4
                        ::/128 ::1/128 ::ffff:0:0/96 64:ff9b::/96 fc00::/7 fe80::/10 ff00::/8].map { |r| IPAddr.new(r) }.freeze

    def private_address?(ip)
      PRIVATE_RANGES.any? { |r| r.include?(ip) }
    end

    # Net::HTTP with the rules above. Tests inject a fake with the same get(uri).
    class Fetcher
      def initialize(resolver: Resolv, cache: Rails.cache, robots: true)
        @resolver = resolver
        @cache = cache
        @robots = robots
      end

      def get(uri)
        redirects = 0
        loop do
          Retrieve.refuse_private!(uri.host, resolver: @resolver)
          throttle!(uri.host)
          return Response.new(status: "BLOCKED", final_url: uri.to_s) if @robots && disallowed?(uri)

          response, body, too_large = request(uri)
          case response
          when Net::HTTPRedirection
            redirects += 1
            return Response.new(status: "BLOCKED", final_url: uri.to_s) if redirects > MAX_REDIRECTS || response["location"].blank?
            uri = URI.join(uri, response["location"])
            raise Refused, "redirect to #{uri}" unless uri.is_a?(URI::HTTP)
            next
          when Net::HTTPSuccess
            return Response.new(status: "TOO_LARGE", final_url: uri.to_s) if too_large
            return Response.new(status: "FETCHED", media_type: response["content-type"].to_s.split(";").first.to_s.strip.downcase.presence || "application/octet-stream", body: body, final_url: uri.to_s)
          when Net::HTTPNotFound, Net::HTTPGone
            return Response.new(status: "NOT_FOUND", final_url: uri.to_s)
          when Net::HTTPClientError
            return Response.new(status: "BLOCKED", final_url: uri.to_s)
          else
            return Response.new(status: "NOT_FOUND", final_url: uri.to_s)
          end
        end
      end

      private

      def request(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        body = +""
        too_large = false
        response = http.start do |conn|
          req = Net::HTTP::Get.new(uri.request_uri, "User-Agent" => Retrieve.user_agent, "Accept" => "text/html, text/plain;q=0.9, */*;q=0.5")
          conn.request(req) do |res|
            res.read_body do |chunk|
              body << chunk
              if body.bytesize > MAX_BYTES
                too_large = true
                break
              end
            end
          end
        end
        [ response, body, too_large ]
      end

      def throttle!(host)
        key = "sources:retrieve:host:#{host}"
        return if @cache.read(key).nil?.tap { |free| @cache.write(key, Time.now.to_i, expires_in: HOST_INTERVAL) if free }

        sleep_seconds = HOST_INTERVAL
        Rails.logger.info("sources:retrieve waiting #{sleep_seconds}s for #{host}")
        sleep(sleep_seconds)
        @cache.write(key, Time.now.to_i, expires_in: HOST_INTERVAL)
      end

      def disallowed?(uri)
        robots = URI::HTTP.build(scheme: uri.scheme, host: uri.host, port: uri.port, path: "/robots.txt")
        robots = URI.parse(robots.to_s.sub(/\Ahttp:/, "https:")) if uri.scheme == "https"
        response, body, = request(robots)
        return false unless response.is_a?(Net::HTTPSuccess)

        Retrieve.robots_disallow?(body, uri.path.presence || "/")
      rescue StandardError
        false
      end
    end

    # A small robots.txt reader: the group for our agent, else "*"; Disallow prefixes; Allow wins on longer match.
    def robots_disallow?(text, path)
      groups = {}
      current = []
      text.to_s.each_line do |line|
        line = line.sub(/#.*/, "").strip
        next if line.empty?
        key, value = line.split(":", 2).map(&:strip)
        next if value.nil?
        case key.to_s.downcase
        when "user-agent" then current = [ value.downcase ]; groups[value.downcase] ||= { allow: [], disallow: [] }
        when "disallow" then current.each { |ua| groups[ua][:disallow] << value unless value.empty? }
        when "allow" then current.each { |ua| groups[ua][:allow] << value unless value.empty? }
        end
      end
      group = groups["galedra"] || groups["*"]
      return false if group.nil?

      allow = group[:allow].select { |p| path.start_with?(p) }.map(&:length).max || -1
      disallow = group[:disallow].select { |p| path.start_with?(p) }.map(&:length).max || -1
      disallow > allow
    end
  end
end
