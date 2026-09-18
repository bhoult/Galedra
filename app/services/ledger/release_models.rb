# frozen_string_literal: true

module Ledger
  # Releases every model in config/scoring/*.json that is not yet released,
  # signed by the system key (spec 05 §14). Shared by ledger:release_models
  # and the demo seeds. Returns [model_name, contribution-or-nil] per config.
  module ReleaseModels
    module_function

    def call
      Scoring::Registry.config_files.map do |path|
        config = Scoring::Registry.load_config(path)
        name = Scoring::Registry.model_name(config)
        next [ name, nil ] if ScoringModel.exists?(name: config["name"], semantic_version: config["semantic_version"])

        envelope = Contributions::Envelope.build(action_type: "RELEASE_SCORING_MODEL", key_pair: Crypto::SystemKey.key_pair,
                                                 payload: Scoring::Registry.release_payload(config))
        [ name, Ledger::Append.call(envelope, custody: Crypto::Custody::SYSTEM).contribution ]
      end
    end
  end
end
