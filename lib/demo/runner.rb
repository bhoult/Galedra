# frozen_string_literal: true

module Demo
  # bin/demo: seeds a demo on a clean log, prints the report, exits non-zero on
  # any FAIL (spec 07 Phase 7, 10 "Success Standard").
  module Runner
    module_function

    def main(argv)
      example = "public-demo"
      reset = false
      argv.each_with_index do |arg, i|
        example = argv[i + 1] == "watchers" ? "watchers" : "public-demo" if arg == "--example"
        reset = true if arg == "--reset"
      end
      failures = run(example: example, reset: reset)
      exit(failures.zero? ? 0 : 1)
    end

    # Truncates every table but schema_migrations (owner role), then genesis
    # and model releases, so the demo runs on a clean database.
    def reset!
      tables = ActiveRecord::Base.connection.tables - %w[schema_migrations ar_internal_metadata]
      Ledger::DatabaseRole.as_owner { ActiveRecord::Base.connection.truncate_tables(*tables) }
    end

    def prepare!
      Ledger::Genesis.ensure!
      Scoring::Registry.config_files.each do |path|
        config = Scoring::Registry.load_config(path)
        next if ScoringModel.exists?(name: config["name"], semantic_version: config["semantic_version"])

        envelope = Contributions::Envelope.build(action_type: "RELEASE_SCORING_MODEL", key_pair: Crypto::SystemKey.key_pair, payload: Scoring::Registry.release_payload(config))
        Ledger::Append.call(envelope, custody: Crypto::Custody::SYSTEM)
      end
    end

    def clean?
      Contribution.where.not(action_type: %w[REGISTER_KEY RELEASE_SCORING_MODEL]).none? && Claim.none?
    end

    def run(example:, reset: false, out: $stdout)
      reset! if reset
      prepare!
      unless clean?
        out.puts "The log already holds contributions. Run with --reset to start from a clean database (development only)."
        return 1
      end
      seeded = example == "watchers" ? Watchers.run : PublicDemo.run
      Report.new(example, seeded, out: out).run
    end
  end
end
