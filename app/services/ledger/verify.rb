# frozen_string_literal: true

module Ledger
  # Recomputes every hash and checks every signature from the log alone
  # (spec 05 §5): public keys are taken from REGISTER_KEY entries as they are
  # met, never from projections. Reports the first break with its seq.
  class Verify
    CHAIN_VERIFIED = "CHAIN_VERIFIED"
    CHAIN_BROKEN = "CHAIN_BROKEN"
    BATCH = 500

    Result = Struct.new(:status, :checked, :head_seq, :head_hash, :first_break, keyword_init: true) do
      def ok? = first_break.nil?
    end

    def self.call = new.call

    # Local checks for one entry (GET /contributions/:id/verify).
    def self.entry(contribution)
      previous = contribution.genesis? ? nil : Contribution.find_by(seq: contribution.seq - 1)
      expected_prev = contribution.genesis? ? Contribution::GENESIS_PREV_HASH : previous&.entry_hash
      recomputed = Entry.hash(seq: contribution.seq, prev_hash: contribution.prev_hash,
                              envelope_hash: contribution.envelope_hash, received_at: contribution.received_at)
      {
        client_signature_ok: client_signature_ok?(contribution),
        server_signature_ok: Entry.server_signature_ok?(contribution.entry_hash, contribution.server_signature),
        chain_ok: contribution.prev_hash == expected_prev && recomputed == contribution.entry_hash &&
                  (contribution.redacted? || (Contributions::Envelope.hash(contribution.envelope) == contribution.envelope_hash &&
                                              Crypto::Hashing.json(contribution.payload) == contribution.payload_hash))
      }
    end

    def self.client_signature_ok?(contribution)
      return false if contribution.redacted?

      public_key = if contribution.action_type == "REGISTER_KEY"
        contribution.payload["public_key"]
      else
        Contributor.find_by(key_id: contribution.signer_key_id)&.public_key
      end
      return false if public_key.nil?

      Crypto::Ed25519.verify(public_key, contribution.signature, Contributions::Envelope.signed_bytes(contribution.envelope))
    end

    def call
      keys = {}
      expected_seq = 0
      prev_hash = Contribution::GENESIS_PREV_HASH
      checked = 0
      head = nil

      each_entry do |c|
        reason = check(c, expected_seq, prev_hash, keys)
        return broken(c, reason, checked) if reason

        keys[c.signer_key_id] = c.payload["public_key"] if c.action_type == "REGISTER_KEY"
        expected_seq += 1
        prev_hash = c.entry_hash
        head = c
        checked += 1
      end

      Result.new(status: CHAIN_VERIFIED, checked: checked, head_seq: head&.seq, head_hash: head&.entry_hash, first_break: nil)
    end

    private

    def each_entry
      last = -1
      loop do
        batch = Contribution.where("seq > ?", last).in_order.limit(BATCH).to_a
        break if batch.empty?

        batch.each { |c| yield c }
        last = batch.last.seq
      end
    end

    def broken(contribution, reason, checked)
      Result.new(status: CHAIN_BROKEN, checked: checked, head_seq: nil, head_hash: nil,
                 first_break: { seq: contribution.seq, reason: reason })
    end

    def check(c, expected_seq, prev_hash, keys)
      return "seq gap: expected #{expected_seq}, found #{c.seq}" unless c.seq == expected_seq
      return "prev_hash does not match the previous entry" unless c.prev_hash == prev_hash
      if c.genesis?
        return "genesis is not the pinned system key's REGISTER_KEY" unless c.action_type == "REGISTER_KEY" &&
                                                                          c.payload&.dig("public_key") == Crypto::SystemKey.public_key
      end
      unless c.redacted?
        return "envelope_hash does not match the stored envelope" unless Contributions::Envelope.hash(c.envelope) == c.envelope_hash
        return "payload_hash does not match the stored payload" unless Crypto::Hashing.json(c.payload) == c.payload_hash &&
                                                                       c.envelope["payload_hash"] == c.payload_hash
        public_key = c.action_type == "REGISTER_KEY" ? c.payload["public_key"] : keys[c.signer_key_id]
        return "signer key was not registered earlier in the log" if public_key.nil?
        return "client signature does not verify" unless Crypto::Ed25519.verify(public_key, c.signature, Contributions::Envelope.signed_bytes(c.envelope))
      end
      recomputed = Entry.hash(seq: c.seq, prev_hash: c.prev_hash, envelope_hash: c.envelope_hash, received_at: c.received_at)
      return "entry_hash does not recompute" unless recomputed == c.entry_hash
      return "server signature does not verify" unless Entry.server_signature_ok?(c.entry_hash, c.server_signature)

      nil
    end
  end
end
