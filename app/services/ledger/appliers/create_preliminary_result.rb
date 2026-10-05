# frozen_string_literal: true

module Ledger
  module Appliers
    # CREATE_PRELIMINARY_RESULT (Stage 45): an assistant's first reading of one
    # claim, from what it already knew, before any source was read into Galedra.
    # Article XIV: a judgment that needs a model enters as an attributed
    # contribution open to audit, so it is signed, projected, replayed and open
    # to takedown like any other. It is not evidence and never reaches a score
    # (Scoring::Watermark::NONE), and its text never reaches a packet.
    #
    # The model is carried in the payload, as declared, because the envelope's
    # `software` object is unusable for it (Stage 27 measured `model_id` as
    # "oauth" 93 times in 600), and in the paste flow the signer is the browser's
    # token, which knows nothing about the assistant that drafted the bundle.
    module CreatePreliminaryResult
      extend Epistemic

      def self.authorize!(validated)
        p = validated.payload
        claim = current_claim!(p, "claim_id")
        reject("SCHEMA_INVALID", path("expectation"), "expected one of #{PreliminaryResult::EXPECTATIONS.join(', ')}") unless PreliminaryResult::EXPECTATIONS.include?(p["expectation"])
        string!(p, "rationale", max: PreliminaryResult::MAX_RATIONALE)
        model = string_or_nil!(p, "model")
        reject("SCHEMA_INVALID", path("model"), "at most #{PreliminaryResult::MAX_MODEL_CHARS} characters") if model && model.length > PreliminaryResult::MAX_MODEL_CHARS
        leads!(p)
        # Outlines are out of scope: a speech or an episode gets counts by
        # state, never a reading of the whole, and its leaves are worked by
        # volunteers who should not be anchored by a first guess.
        if ClaimPlacement.live.exists?(claim_id: claim.id)
          reject("PRELIMINARY_NOT_FOR_OUTLINES", path("claim_id"), "this claim is placed in an outline; a preliminary result is for a short check only, so record the claim's evidence instead")
        end
        return unless claim.claim_type == "NORMATIVE"

        reject("PRELIMINARY_NOT_CHECKABLE", path("claim_id"), "a NORMATIVE claim is not a checkable fact, and its page already says so; leave preliminary off it")
      end

      def self.leads!(p)
        leads = p.fetch("leads", [])
        unless leads.is_a?(Array) && leads.size <= PreliminaryResult::MAX_LEADS
          reject("SCHEMA_INVALID", path("leads"), "expected an array of at most #{PreliminaryResult::MAX_LEADS} links")
        end
        leads.each_with_index do |lead, i|
          next if lead.is_a?(String) && lead.length <= PreliminaryResult::MAX_LEAD_CHARS && web_url?(lead)

          reject("SCHEMA_INVALID", "#{path('leads')}[#{i}]", "expected an http or https link of at most #{PreliminaryResult::MAX_LEAD_CHARS} characters")
        end
      end

      def self.web_url?(text)
        uri = URI.parse(text)
        %w[http https].include?(uri.scheme) && uri.host.present?
      rescue URI::InvalidURIError
        false
      end

      def self.apply_payload(c, p, index = nil)
        PreliminaryResult.create!(
          id: row_id(c, "preliminary", index), contribution_id: c.id, created_seq: c.seq,
          claim_id: p["claim_id"], expectation: p["expectation"], rationale: p["rationale"],
          leads: p.fetch("leads", []), model: p["model"].presence, principal_contributor_id: c.principal_contributor_id
        )
      end
    end
  end
end
