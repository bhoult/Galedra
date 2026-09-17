# frozen_string_literal: true

module Ledger
  # The only write path into the log (spec 02 §1.1, §1.2). Validates, takes the
  # advisory lock, assigns a gap-free seq, builds and signs the chain entry,
  # persists, and applies projections in the same transaction. A duplicate
  # (same idempotency key) returns the original contribution.
  class Append
    Result = Struct.new(:contribution, :created, keyword_init: true)

    def self.call(envelope, custody: Crypto::Custody::SELF)
      new(envelope, custody).call
    end

    def initialize(envelope, custody)
      @envelope = envelope
      @custody = custody
    end

    def call
      if (existing = duplicate)
        return Result.new(contribution: existing, created: false)
      end

      validated = Contributions::ValidateEnvelope.call(@envelope)
      custody!(validated)

      Contribution.transaction do
        lock!
        if (existing = Contribution.find_by(idempotency_key: validated.idempotency_key))
          next Result.new(contribution: existing, created: false)
        end

        head = Contribution.in_order.last
        genesis!(validated, head)
        applier = Appliers.for(validated.action_type)
        applier&.authorize!(validated)

        seq = head ? head.seq + 1 : 0
        prev_hash = head ? head.entry_hash : Contribution::GENESIS_PREV_HASH
        received_at = Time.now.utc.floor(6)
        entry_hash = Entry.hash(seq: seq, prev_hash: prev_hash, envelope_hash: validated.envelope_hash, received_at: received_at)

        contribution = Contribution.create!(
          seq: seq,
          signer_key_id: validated.signer_key_id,
          contributor_id: validated.contributor&.id,
          action_class: validated.action_class,
          action_type: validated.action_type,
          payload: validated.payload,
          payload_hash: validated.payload_hash,
          envelope: @envelope,
          envelope_hash: validated.envelope_hash,
          signature: @envelope["signature"],
          task_id: @envelope["task_id"],
          task_packet_hash: @envelope["task_packet_hash"],
          software: @envelope["software"],
          custody: @custody,
          client_created_at: Time.iso8601(@envelope["client_created_at"]),
          received_at: received_at,
          prev_hash: prev_hash,
          entry_hash: entry_hash,
          server_signature: Entry.sign(entry_hash),
          idempotency_key: validated.idempotency_key,
          current_status: validated.action_class == Contribution::CONTROL ? Contribution::ACCEPTED : Contribution::PENDING
        )

        Apply.call(contribution)
        Result.new(contribution: contribution, created: true)
      end
    end

    private

    def reject(code, path, detail)
      raise Rejected.new([ { code: code, path: path, detail: detail } ])
    end

    # A resubmission of an already-logged envelope returns the original
    # (spec 04 §4.2) before any other check, so the client sees the same answer
    # every time.
    def duplicate
      return nil unless @envelope.is_a?(Hash)

      key = Contributions::Envelope.idempotency_key(signer_key_id: @envelope["signer_key_id"].to_s,
                                                    task_id: @envelope["task_id"], payload_hash: @envelope["payload_hash"].to_s)
      Contribution.find_by(idempotency_key: key)
    end

    # Block-scoped: Model.connection would lease the connection to the thread
    # until an executor releases it, which starves other threads.
    def lock!
      Contribution.with_connection { |c| c.execute("SELECT pg_advisory_xact_lock(#{ADVISORY_LOCK_KEY})") }
    end

    # SYSTEM custody is exactly the system key; SERVER custody is set only by
    # server-side callers (API submissions are SELF).
    def custody!(validated)
      reject("SCHEMA_INVALID", "$", "unknown custody") unless Crypto::Custody::ALL.include?(@custody)
      system_signer = validated.signer_key_id == Crypto::SystemKey.key_id
      if system_signer != (@custody == Crypto::Custody::SYSTEM)
        reject("NOT_AUTHORIZED", "$.signer_key_id", "the system key signs only with SYSTEM custody, and nothing else does")
      end
    end

    # seq 0 is the system key's self-signed REGISTER_KEY, pinned in deployment
    # configuration (spec 02 §1.2a). Nothing else may enter an empty log, and a
    # log whose genesis does not match the pinned key is refused entirely.
    def genesis!(validated, head)
      if head.nil?
        unless validated.action_type == "REGISTER_KEY" && validated.payload["kind"] == Contributor::SYSTEM &&
               validated.public_key == Crypto::SystemKey.public_key && @custody == Crypto::Custody::SYSTEM
          reject("GENESIS_REQUIRED", "$", "an empty log accepts only the pinned system key's REGISTER_KEY")
        end
      else
        Genesis.verify!(Contribution.find_by!(seq: 0))
        if validated.action_type == "REGISTER_KEY" && validated.payload["kind"] == Contributor::SYSTEM
          reject("NOT_AUTHORIZED", "$.payload.kind", "only the genesis entry registers a SYSTEM key")
        end
      end
    end
  end
end
