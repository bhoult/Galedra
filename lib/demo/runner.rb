# frozen_string_literal: true

module Demo
  # bin/demo: seeds a demo on a clean log, prints the report, exits non-zero on
  # any FAIL (spec 07 Phase 7, 10 "Success Standard").
  module Runner
    EXAMPLES = %w[public-demo watchers].freeze
    USAGE = "usage: bin/demo [--example #{EXAMPLES.join('|')}] [--reset]"

    module_function

    def main(argv)
      example = "public-demo"
      reset = false
      args = argv.dup
      until args.empty?
        case (arg = args.shift)
        when "--example" then example = args.shift
        when "--reset" then reset = true
        else abort("#{USAGE}\nunknown argument #{arg.inspect}")
        end
      end
      abort("#{USAGE}\nunknown example #{example.inspect}") unless EXAMPLES.include?(example)
      exit(run(example: example, reset: reset).zero? ? 0 : 1)
    end

    # Truncates every table but schema_migrations (owner role), then genesis
    # and model releases, so the demo runs on a clean database. Development
    # and test only: the log is append-only everywhere else (CLAUDE.md invariant 3).
    def reset!
      raise "bin/demo --reset truncates the whole log and runs only in development or test, not #{Rails.env}" unless Rails.env.local?

      tables = ActiveRecord::Base.connection.tables - %w[schema_migrations ar_internal_metadata]
      Ledger::DatabaseRole.as_owner { ActiveRecord::Base.connection.truncate_tables(*tables) }
    end

    def prepare!
      Ledger::Genesis.ensure!
      Ledger::ReleaseModels.call
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
