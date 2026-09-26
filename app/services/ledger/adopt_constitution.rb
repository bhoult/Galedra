# frozen_string_literal: true

module Ledger
  # Records the constitution this node serves as a signed AMEND_CONSTITUTION,
  # unless that text is already the one recorded. Returns the contribution, or
  # nil when there was nothing to record.
  module AdoptConstitution
    module_function

    def call(note: nil)
      constitution = Governance::Constitution.new
      return nil if Governance::Constitution.recorded_hash == constitution.digest

      payload = { "version" => constitution.version, "constitution_hash" => constitution.digest }
      payload["note"] = note if note.present?
      envelope = Contributions::Envelope.build(action_type: "AMEND_CONSTITUTION", key_pair: Crypto::SystemKey.key_pair, payload: payload)
      Ledger::Append.call(envelope, custody: Crypto::Custody::SYSTEM).contribution
    end
  end
end
