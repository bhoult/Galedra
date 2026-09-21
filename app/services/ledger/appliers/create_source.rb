# frozen_string_literal: true

module Ledger
  module Appliers
    # CREATE_SOURCE (spec 02 §3.2). Content travels in the payload; its hash is
    # over the UTF-8 bytes and is independent of any storage backend.
    module CreateSource
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        in_task = validated.respond_to?(:in_task) && validated.in_task
        enum!(p, "source_type", Source::TYPES)
        string!(p, "title", max: 1_000)
        %w[creator publisher canonical_uri license lineage_key].each { |k| string_or_nil!(p, k) }
        publication_date!(p)
        hash!(p, "external_ids", default: {})
        hash!(p, "metadata", default: {})
        time_or_nil!(p, "retrieved_at")
        if in_task
          # 04 §6 step 9: the server never fetches agent-supplied URLs; agent
          # sources are metadata-only until a human or trusted job imports content.
          reject("CONTENT_NOT_ALLOWED", path("content"), "sources created inside a task are metadata-only (retrieval_pending)") if p.key?("content") || p.key?("content_hash")
          string_or_nil!(p, "canonical_uri")
        elsif p.key?("content")
          content = string!(p, "content", max: Source::MAX_CONTENT_CHARS)
          unless p["content_hash"] == Crypto::Hashing.bytes(content)
            reject("CONTENT_HASH_MISMATCH", path("content_hash"), "does not equal sha256 of the content bytes")
          end
        else
          # Stage 13: a source by reference. The link and the time of reading
          # are recorded; the text is not (01 §7). Excerpts live on QUOTE and
          # TRANSCRIPTION locations, each with its own hash. A hash of the
          # page bytes is recorded when the reader had the bytes; a reader
          # that only saw a rendering omits it rather than inventing one.
          reject("SCHEMA_INVALID", path("content"), "give content, or canonical_uri with retrieved_at for a source held by reference") unless p["canonical_uri"].present? && p["retrieved_at"].present?
          reject("SCHEMA_INVALID", path("content_hash"), "expected sha256:<hex> of the bytes that were read, or omit it") unless p["content_hash"].nil? || Crypto::Hashing.valid?(p["content_hash"].to_s)
        end
        live!(Source, p, "previous_version_id") unless p["previous_version_id"].nil?
      end

      def self.publication_date!(p)
        value = p["publication_date"]
        return if value.nil?

        Date.iso8601(value.to_s)
      rescue Date::Error
        reject("SCHEMA_INVALID", path("publication_date"),
               "expected YYYY-MM-DD, the whole date. If you only know the year or the month, leave it out rather than " \
               "padding it: a day nobody established is worse here than a blank.")
      end

      def self.apply_payload(c, p, index = nil)
        source = Source.create!(
          id: row_id(c, "source", index), contribution_id: c.id, created_seq: c.seq, retrieval_pending: !p.key?("content"),
          source_type: p["source_type"], title: p["title"], creator: p["creator"], publisher: p["publisher"],
          publication_date: p["publication_date"], canonical_uri: p["canonical_uri"],
          external_ids: p.fetch("external_ids", {}), content: p["content"], content_hash: p["content_hash"],
          retrieved_at: p["retrieved_at"], license: p["license"], previous_version_id: p["previous_version_id"],
          lineage_key: p["lineage_key"], metadata: p.fetch("metadata", {})
        )
        # Stage 17: a source by reference, outside a task, is fetched later by
        # Galedra's own job (never on an assistant's say-so). Not during replay.
        if source.retrieval_pending && index.nil? && source.canonical_uri.present? && Sources::Retrieve.enabled? && !Ledger.replaying?
          RetrieveSourceJob.perform_later(source.id, source.created_seq)
        end
        source
      end
    end
  end
end
