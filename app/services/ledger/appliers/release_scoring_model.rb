# frozen_string_literal: true

module Ledger
  module Appliers
    # RELEASE_SCORING_MODEL (spec 05 §14): signed by the system key, carrying the
    # full config, its hash, the hash of the scorer code now running, and the
    # test-suite result hash. Weights never change without a new version.
    module ReleaseScoringModel
      extend Checks

      def self.authorize!(validated)
        reject("NOT_AUTHORIZED", "$.signer_key_id", "only the system key releases scoring models") unless validated.contributor&.system?
        p = validated.payload
        config = hash!(p, "config")
        begin
          Scoring::Registry.validate!(config)
        rescue Scoring::Registry::Invalid => e
          reject("CONFIG_INVALID", path("config"), e.message)
        end
        reject("SCHEMA_INVALID", path("name"), "must equal config.name") unless p["name"] == config["name"]
        reject("SCHEMA_INVALID", path("semantic_version"), "must equal config.semantic_version") unless p["semantic_version"] == config["semantic_version"]
        reject("CONFIG_HASH_MISMATCH", path("config_hash"), "does not equal sha256 of the canonical config") unless p["config_hash"] == Crypto::Hashing.json(config)
        reject("CODE_HASH_MISMATCH", path("code_hash"), "does not equal the hash of the scorer code now running (#{Scoring::Registry.code_hash})") unless p["code_hash"] == Scoring::Registry.code_hash
        string_or_nil!(p, "test_suite_result_hash")
        if ScoringModel.exists?(name: p["name"], semantic_version: p["semantic_version"])
          reject("ALREADY_RELEASED", path("semantic_version"), "#{p['name']}@#{p['semantic_version']} is already released")
        end
      end

      def self.apply(c)
        p = c.payload
        ScoringModel.create!(
          id: Ids.derive(c.id, "scoring_model"), contribution_id: c.id, released_seq: c.seq,
          name: p["name"], semantic_version: p["semantic_version"], config: p["config"],
          config_hash: p["config_hash"], code_hash: p["code_hash"], test_suite_result_hash: p["test_suite_result_hash"],
          release_signature: c.signature
        )
      end
    end
  end
end
