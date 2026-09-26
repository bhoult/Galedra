# frozen_string_literal: true

module Ledger
  module Appliers
    # AMEND_CONSTITUTION (constitution Article XXV): signed by the system key,
    # naming the version and the hash of the text this node now serves. An
    # amendment takes effect only once recorded here, so the log, not the file on
    # disk, says which principles were adopted and when; `/api/v1/meta` compares
    # the two. Checked against the running text at append only, as a model's
    # code_hash is: replay re-applies without asking the file again.
    module AmendConstitution
      extend Checks

      def self.authorize!(validated)
        reject("NOT_AUTHORIZED", "$.signer_key_id", "only the system key records the constitution") unless validated.contributor&.system?
        p = validated.payload
        string!(p, "version", max: 20)
        string!(p, "constitution_hash", max: 80)
        string_or_nil!(p, "note")
        running = Governance::Constitution.new
        reject("VERSION_MISMATCH", path("version"), "does not equal the version of the text served (#{running.version})") unless p["version"] == running.version
        reject("CONSTITUTION_HASH_MISMATCH", path("constitution_hash"), "does not equal the hash of the text served (#{running.digest})") unless p["constitution_hash"] == running.digest
        return unless Governance::Constitution.recorded_hash == p["constitution_hash"]

        reject("ALREADY_RECORDED", path("constitution_hash"), "this text is already the one recorded")
      end

      # Nothing to project: the contribution is the record.
      def self.apply(_contribution); end
    end
  end
end
