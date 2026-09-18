# frozen_string_literal: true

module Ledger
  module Appliers
    # CREATE_SOURCE_LOCATION (spec 02 §3.2). For CHAR_RANGE on stored text the
    # excerpt must equal the stored slice (character offsets) and excerpt_hash
    # must match; this is what defeats fabricated quotations (05 §1 threats 2–3).
    module CreateSourceLocation
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        source = live!(Source, p, "source_id")
        type = enum!(p, "locator_type", SourceLocation::LOCATOR_TYPES)
        locator = hash!(p, "locator")
        excerpt = string_or_nil!(p, "excerpt")
        string_or_nil!(p, "excerpt_hash")

        reject("LOCATOR_INVALID", path("locator_type"), "CHAR_RANGE needs stored content; this source is retrieval_pending") if type == "CHAR_RANGE" && source.content.nil?
        if type == "CHAR_RANGE"
          start = locator["start"]
          finish = locator["end"]
          unless start.is_a?(Integer) && finish.is_a?(Integer) && start >= 0 && finish > start && finish <= source.content_length
            reject("LOCATOR_INVALID", path("locator"), "start/end must be character offsets within 0..#{source.content_length}")
          end
          reject("SCHEMA_INVALID", path("excerpt"), "required for CHAR_RANGE") if excerpt.nil?
          reject("EXCERPT_MISMATCH", path("excerpt"), "does not equal the stored slice") unless excerpt == source.slice(start, finish)
        end
        reject("SCHEMA_INVALID", path("excerpt"), "required for #{type}") if %w[QUOTE TRANSCRIPTION].include?(type) && excerpt.blank?
        if excerpt && p["excerpt_hash"] != Crypto::Hashing.bytes(excerpt)
          reject("EXCERPT_HASH_MISMATCH", path("excerpt_hash"), "does not equal sha256 of the excerpt bytes")
        end
      end

      def self.apply_payload(c, p, index = nil)
        SourceLocation.create!(
          id: row_id(c, "location", index), contribution_id: c.id, created_seq: c.seq,
          source_id: p["source_id"], locator_type: p["locator_type"], locator: p["locator"],
          excerpt: p["excerpt"], excerpt_hash: p["excerpt_hash"]
        )
      end
    end
  end
end
