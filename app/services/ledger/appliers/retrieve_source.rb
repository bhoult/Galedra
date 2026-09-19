# frozen_string_literal: true

module Ledger
  module Appliers
    # RETRIEVE_SOURCE (Stage 17): a control entry signed by the system key
    # recording what Galedra's own fetch of a source held by reference found.
    # The only input to a fetch is a link already in the log; an assistant can
    # never ask for one. The reader's source row keeps its own hash; the
    # server's sits beside it. Page text never enters the log.
    module RetrieveSource
      extend Checks

      def self.authorize!(validated)
        reject("NOT_AUTHORIZED", "$.signer_key_id", "only the system key records a retrieval") unless validated.contributor&.system?
        p = validated.payload
        source = live!(Source, p, "source_id")
        reject("SCHEMA_INVALID", path("source_id"), "this source carries stored content; only sources held by reference are retrieved") unless source.content.nil?
        time!(p, "fetched_at")
        outcome = enum!(p, "outcome", SourceRetrieval::OUTCOMES)
        if outcome == "FETCHED"
          reject("SCHEMA_INVALID", path("content_hash"), "expected sha256:<hex> of the bytes received") unless Crypto::Hashing.valid?(p["content_hash"].to_s)
          integer!(p, "content_length", range: 0..)
        else
          reject("SCHEMA_INVALID", path("content_hash"), "only a FETCHED retrieval carries a hash") unless p["content_hash"].nil?
          integer_or_nil!(p, "content_length")
        end
        string_or_nil!(p, "media_type")
        string_or_nil!(p, "final_url")
        excerpts = p.fetch("excerpts", [])
        reject("SCHEMA_INVALID", path("excerpts"), "expected an array") unless excerpts.is_a?(Array)
        excerpts.each_with_index do |e, i|
          reject("SCHEMA_INVALID", "#{path('excerpts')}[#{i}]", "expected {location_id, found}") unless e.is_a?(Hash)
          location = SourceLocation.find_by(id: e["location_id"].to_s)
          reject("TARGET_UNKNOWN", "#{path('excerpts')}[#{i}].location_id", "no such location on this source") if location.nil? || location.source_id != source.id
          reject("SCHEMA_INVALID", "#{path('excerpts')}[#{i}].found", "expected one of #{SourceRetrieval::FINDINGS.join(', ')}") unless SourceRetrieval::FINDINGS.include?(e["found"])
        end
      end

      def self.apply(c)
        p = c.payload
        source = Source.find(p["source_id"])
        SourceRetrieval.create!(
          id: Ids.derive(c.id, "retrieval"), contribution_id: c.id, source_id: source.id, source_created_seq: source.created_seq,
          outcome: p["outcome"], fetched_at: p["fetched_at"], content_hash: p["content_hash"], content_length: p["content_length"],
          media_type: p["media_type"], final_url: p["final_url"], excerpts: p.fetch("excerpts", []).map { |e| { "location_id" => e["location_id"], "found" => e["found"] } },
          created_seq: c.seq
        )
        source.update!(retrieval_pending: false) if p["outcome"] == "FETCHED"
      end
    end
  end
end
