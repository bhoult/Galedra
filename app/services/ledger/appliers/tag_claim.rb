# frozen_string_literal: true

module Ledger
  module Appliers
    # TAG_CLAIM (IMPLEMENTATION.md Stage 15): places a claim under one to five
    # topics from config/topics.yml. A judgment, so a signed, attributable,
    # challengeable contribution. Accepted automatically for the principal's
    # own claim; a tag on someone else's claim stays PENDING like a proposal.
    # A later tag by the same principal replaces that principal's earlier one.
    module TagClaim
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        current_claim!(p, "claim_id")
        topics = p["topics"]
        reject("SCHEMA_INVALID", path("topics"), "expected an array of 1..#{Topics::MAX_PER_CLAIM} topic paths") unless topics.is_a?(Array) && topics.any? && topics.size <= Topics::MAX_PER_CLAIM && topics.all?(String)
        reject("SCHEMA_INVALID", path("topics"), "topics must be distinct") unless topics.uniq.size == topics.size
        unknown = topics.reject { |t| Topics.valid?(t) }
        reject("TOPIC_UNKNOWN", path("topics"), "not in the vocabulary: #{unknown.join(', ')}") if unknown.any?
        string_or_nil!(p, "note")

        allowed = validated.delegation&.permissions&.dig("topics")
        return if allowed.blank?

        outside = topics.reject { |t| Array(allowed).any? { |prefix| t == prefix || t.start_with?("#{prefix}/") } }
        reject("DELEGATION_INVALID", path("topics"), "this delegation may not tag #{outside.join(', ')}") if outside.any?
      end

      # The system's own backfill tags are accepted too: they are guesses, say so
      # in their note, and are as visible and replaceable as any other tag.
      def self.auto_accept?(validated)
        return true if validated.contributor&.system?

        claim = Claim.find(validated.payload["claim_id"])
        principal = validated.contributor&.human? ? validated.contributor&.id : validated.delegation&.principal_contributor_id
        principal.present? && claim.contribution.principal_contributor_id == principal
      end

      def self.apply_payload(c, p, index = nil)
        principal_id = c.principal_contributor_id
        ClaimTopic.where(claim_id: p["claim_id"], principal_contributor_id: principal_id, replaced_seq: nil).update_all(replaced_seq: c.seq)
        p["topics"].each_with_index.map do |topic, i|
          ClaimTopic.create!(
            id: row_id(c, "topic", index ? "#{index}-#{i}" : i), contribution_id: c.id, created_seq: c.seq,
            claim_id: p["claim_id"], topic: topic, principal_contributor_id: principal_id, note: p["note"]
          )
        end
      end
    end
  end
end
