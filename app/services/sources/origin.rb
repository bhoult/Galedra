# frozen_string_literal: true

module Sources
  # Which thing in the world a source is a record of (Stage 35).
  #
  # Two people recording the same URL create two Source rows, and nothing
  # deduplicates them: on this node four URLs became fifteen rows. That is
  # correct as a record — they are two honest contributions by different people
  # at different times — but wrong as an origin, because independence is about
  # where evidence came from, and one URL is one place. Counting the same URL
  # twice is the double counting Invariant 6 forbids.
  #
  # Derived at read time rather than written into a column: the log is untouched,
  # no contribution is rewritten, and replay is unaffected. An explicit
  # lineage_key always wins, because a person saying two records share an origin
  # knows something a URL cannot express.
  module Origin
    TRACKING = %w[utm_source utm_medium utm_campaign utm_term utm_content gclid fbclid ref si].freeze

    module_function

    def key_for(source)
      return nil if source.nil?
      return "lineage:#{source.lineage_key}" if source.lineage_key.present?

      normalised = normalise(source.canonical_uri)
      normalised ? "uri:#{normalised}" : "source:#{source.id}"
    end

    # Same page, written differently: case in scheme and host, a default port, a
    # trailing slash, and the tracking parameters a link picks up in transit.
    # Deliberately conservative — anything that could be a different page stays a
    # different origin.
    def normalise(uri)
      return nil if uri.blank?

      parsed = URI.parse(uri.strip)
      return nil unless parsed.host.present? && parsed.scheme.present?

      host = parsed.host.downcase.sub(/\A www\. /x, "")
      port = parsed.port && parsed.port != parsed.default_port ? ":#{parsed.port}" : ""
      path = parsed.path.to_s.chomp("/")
      query = clean_query(parsed.query)
      "#{parsed.scheme.downcase}://#{host}#{port}#{path}#{query.present? ? "?#{query}" : ''}"
    rescue URI::InvalidURIError
      nil
    end

    def clean_query(query)
      return nil if query.blank?

      URI.decode_www_form(query).reject { |k, _| TRACKING.include?(k.downcase) }.sort.map { |k, v| "#{k}=#{v}" }.join("&")
    rescue ArgumentError
      query
    end
  end
end
